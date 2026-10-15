import '../di/key.dart';
import 'grund_error.dart';

/// A module graph that is invalid, found before any factory runs.
sealed class GraphError extends GrundError {
  /// Creates the error.
  const GraphError();
}

/// Modules import each other in a cycle.
final class CircularModuleImportError extends GraphError {
  /// Creates the error for [cycle], the modules from the first repeated one
  /// back to itself.
  const CircularModuleImportError(this.cycle);

  /// The modules of the cycle, the first one repeated at the end.
  final List<String> cycle;

  @override
  String get message =>
      'Modules import each other in a cycle: ${cycle.join(' -> ')}.';
}

/// One module identity is imported twice with a different shape.
final class ConflictingModuleError extends GraphError {
  /// Creates the error for [module].
  const ConflictingModuleError(this.module);

  /// The identity of the module.
  final String module;

  @override
  String get message =>
      'Module $module is imported twice with a different shape. Instances of '
      'one module class must declare the same imports, bindings and exports; '
      'give them different qualifiers if they are meant to be different '
      'modules.';
}

/// A module declares one key twice.
final class DuplicateBindingError extends GraphError {
  /// Creates the error for [key] declared twice in [module].
  const DuplicateBindingError({required this.key, required this.module});

  /// The key declared twice.
  final Key<Object> key;

  /// The module that declares it.
  final String module;

  @override
  String get message =>
      'Module $module declares $key more than once. Give one of the bindings '
      'a name.';
}

/// A module exports something it neither declares nor imports.
final class InvalidExportError extends GraphError {
  /// Creates the error for [export] of [module].
  const InvalidExportError({required this.export, required this.module});

  /// The offending entry: a key, a module, or something else.
  final Object export;

  /// The exporting module.
  final String module;

  @override
  String get message =>
      'Module $module exports $export, which it neither declares nor '
      'imports. Exports are keys of its own bindings or modules from its '
      'imports.';
}

/// Several imported modules export the same key.
final class AmbiguousProviderError extends GraphError {
  /// Creates the error for [key] seen from [module].
  const AmbiguousProviderError({
    required this.key,
    required this.module,
    required this.owners,
  });

  /// The ambiguous key.
  final Key<Object> key;

  /// The module that sees it twice.
  final String module;

  /// The modules that provide it, sorted.
  final List<String> owners;

  @override
  String get message =>
      '$key is exported by ${owners.join(' and ')}, so module $module cannot '
      'tell which one it means. Declare $key in $module to choose, or name '
      'the bindings.';
}

/// Nothing in the graph provides a key that is required.
final class MissingProviderError extends GraphError {
  /// Creates the error for [key] required in [module].
  const MissingProviderError({
    required this.key,
    required this.module,
    this.requiredBy,
  });

  /// The missing key.
  final Key<Object> key;

  /// The module that needs it.
  final String module;

  /// The binding that needs it, when known.
  final Key<Object>? requiredBy;

  @override
  String get message {
    final by = requiredBy == null ? '' : ', required by $requiredBy';
    return 'No provider for $key is visible in module $module$by. Declare '
        'it there, or import a module that exports it.';
  }
}

/// A key exists in the graph but the requiring module cannot see it.
final class ProviderNotVisibleError extends GraphError {
  /// Creates the error for [key] required in [module].
  const ProviderNotVisibleError({
    required this.key,
    required this.module,
    required this.requiredBy,
    required this.declaredIn,
    required this.importChain,
  });

  /// The invisible key.
  final Key<Object> key;

  /// The module that needs it.
  final String module;

  /// The binding that needs it.
  final Key<Object> requiredBy;

  /// The modules that declare it.
  final List<String> declaredIn;

  /// Modules from [module] down to a declaring one when it is imported
  /// indirectly; empty when it is not imported at all.
  final List<String> importChain;

  @override
  String get message {
    final where = declaredIn.join(' and ');
    final hint = importChain.isEmpty
        ? 'import $where into $module and export $key from it'
        : 'it is only reachable through ${importChain.join(' -> ')}; '
              'export $key from the module that imports $where';
    return '$key (required by $requiredBy) is declared in $where but module '
        '$module cannot see it: $hint.';
  }
}

/// Bindings depend on each other in a cycle.
final class CircularDependencyError extends GraphError {
  /// Creates the error for [cycle], the first key repeated at the end.
  const CircularDependencyError(this.cycle);

  /// The keys of the cycle.
  final List<Key<Object>> cycle;

  @override
  String get message =>
      'Bindings depend on each other in a cycle: ${cycle.join(' -> ')}.';
}

/// A singleton holds on to something that lives only for one call.
final class CaptiveDependencyError extends GraphError {
  /// Creates the error for [singleton] reaching [scoped] along [path].
  const CaptiveDependencyError({
    required this.singleton,
    required this.scoped,
    required this.path,
  });

  /// The singleton that would capture the instance.
  final Key<Object> singleton;

  /// The call-scoped key it reaches.
  final Key<Object> scoped;

  /// The keys from [singleton] to [scoped].
  final List<Key<Object>> path;

  @override
  String get message =>
      'Singleton $singleton depends on the call-scoped $scoped '
      '(${path.join(' -> ')}). A singleton outlives a call and would keep a '
      'stale instance; make it Scoped, or resolve $scoped from a call '
      'context.';
}

/// An override replaces a key that no module declares.
final class UnusedOverrideError extends GraphError {
  /// Creates the error for [key].
  const UnusedOverrideError(this.key);

  /// The key of the override.
  final Key<Object> key;

  @override
  String get message =>
      'The override for $key matches no binding of the module graph.';
}
