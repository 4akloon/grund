import 'module.dart';

/// Root of every error raised by grund itself.
abstract base class GrundError implements Exception {
  /// Creates an error.
  const GrundError();

  /// Human-readable explanation, suitable for logs.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Errors raised while building the module graph or resolving providers.
sealed class InjectionError extends GrundError {
  /// Creates an injection error.
  const InjectionError();
}

/// Two different modules (by structure) share one id.
final class DuplicateModuleIdError extends InjectionError {
  /// Creates the error for [id].
  const DuplicateModuleIdError(this.id);

  /// The conflicting id.
  final String id;

  @override
  String get message =>
      'Two different modules share the id "$id". A dynamic module imported '
      'in several places must be configured identically everywhere.';
}

/// Module imports form a cycle.
final class CircularModuleImportError extends InjectionError {
  /// Creates the error for [cycle].
  const CircularModuleImportError(this.cycle);

  /// Module ids forming the cycle; first and last are the same module.
  final List<String> cycle;

  @override
  String get message =>
      'Module imports form a cycle: ${cycle.join(' -> ')}. '
      'Move the shared providers into a third module imported by both.';
}

/// One module declares the same key twice.
final class DuplicateProviderError extends InjectionError {
  /// Creates the error.
  const DuplicateProviderError({required this.key, required this.moduleId});

  /// The duplicated key.
  final Object key;

  /// The module that declares it twice.
  final String moduleId;

  @override
  String get message =>
      'Module "$moduleId" declares ${describeKey(key)} more than once.';
}

/// An `exports` entry is neither an own provider nor an imported module.
final class InvalidExportError extends InjectionError {
  /// Creates the error.
  const InvalidExportError({required this.export, required this.moduleId});

  /// The offending export entry.
  final Object export;

  /// The exporting module.
  final String moduleId;

  @override
  String get message {
    final e = export; // local copy: public fields do not promote
    final what = e is Module ? 'module "${e.id}"' : describeKey(e);
    return 'Module "$moduleId" exports $what, which is neither one of its '
        'providers nor one of its imports.';
  }
}

/// Several modules export the same key into one scope tier of a module.
///
/// Scope order (own providers, then imports, then globals) is not ambiguity;
/// two different owners within the imports, or within the globals, are.
final class AmbiguousProviderError extends InjectionError {
  /// Creates the error.
  const AmbiguousProviderError({
    required this.key,
    required this.moduleId,
    required this.owners,
  });

  /// The key that is visible from several modules.
  final Object key;

  /// The importing module in which the key is ambiguous.
  final String moduleId;

  /// Ids of the modules that declare [key], sorted.
  final List<String> owners;

  @override
  String get message =>
      'Provider ${describeKey(key)} is visible in module "$moduleId" from '
      'several modules: ${owners.join(', ')}. Import only one of them, or '
      'alias with a Token.';
}

/// Nothing in scope provides the requested key.
final class MissingProviderError extends InjectionError {
  /// Creates the error.
  const MissingProviderError({
    required this.key,
    required this.moduleId,
    required this.chain,
    this.definedIn = const [],
  });

  /// The key that could not be resolved.
  final Object key;

  /// The module whose injector was asked.
  final String moduleId;

  /// Keys being resolved when the lookup failed, innermost first
  /// (`[UsersRepo, UsersService]` means UsersService needed UsersRepo,
  /// which needed [key]).
  final List<Object> chain;

  /// Modules that declare [key] but do not expose it to [moduleId].
  final List<String> definedIn;

  @override
  String get message {
    final buffer = StringBuffer(
      'No provider for ${describeKey(key)} in module "$moduleId"',
    );
    if (chain.isNotEmpty) {
      buffer.write(' (resolving: ${chain.map(describeKey).join(' <- ')})');
    }
    buffer.write('.');
    if (definedIn.isNotEmpty) {
      buffer.write(
        ' It is declared in module(s) [${definedIn.join(', ')}]; export it '
        'there and import that module into "$moduleId".',
      );
    }
    return buffer.toString();
  }
}

/// Providers depend on each other in a cycle.
final class CircularDependencyError extends InjectionError {
  /// Creates the error for [cycle].
  const CircularDependencyError(this.cycle);

  /// Keys forming the cycle; first and last are the same key.
  final List<Object> cycle;

  @override
  String get message =>
      'Circular dependency: ${cycle.map(describeKey).join(' -> ')}.';
}

/// A synchronous `get` asked for an async provider that had not finished
/// starting.
final class AsyncProviderNotReadyError extends InjectionError {
  /// Creates the error.
  const AsyncProviderNotReadyError({
    required this.key,
    required this.moduleId,
    required this.chain,
  });

  /// The async key.
  final Object key;

  /// The module that declares [key].
  final String moduleId;

  /// Keys being resolved, innermost first.
  final List<Object> chain;

  @override
  String get message {
    final who = chain.isEmpty
        ? 'it was requested'
        : '${describeKey(chain.first)} asked for it';
    return 'Provider ${describeKey(key)} (module "$moduleId") is async and '
        'was not ready when $who: a synchronous get ran before it finished '
        'starting. Await Container.create before using the container. If '
        'this happened inside a factory during startup, declare the async '
        'provider earlier in the same module or in an imported module '
        '(global modules already start first).';
  }
}

/// A provider factory threw.
final class ProviderCreationError extends InjectionError {
  /// Creates the error.
  const ProviderCreationError({
    required this.key,
    required this.moduleId,
    required this.chain,
    required this.error,
    required this.stackTrace,
  });

  /// The provider whose factory threw.
  final Object key;

  /// The module that declares it.
  final String moduleId;

  /// Keys being resolved, innermost first.
  final List<Object> chain;

  /// The original error.
  final Object error;

  /// The original stack trace.
  final StackTrace stackTrace;

  @override
  String get message =>
      'Factory for ${describeKey(key)} in module "$moduleId" threw: $error'
      '${chain.isEmpty ? '' : ' (resolving: ${chain.map(describeKey).join(' <- ')})'}';
}

/// No module with the given id exists in the container.
final class UnknownModuleError extends InjectionError {
  /// Creates the error for [id].
  const UnknownModuleError(this.id);

  /// The requested id.
  final String id;

  @override
  String get message => 'No module with id "$id" in this container.';
}
