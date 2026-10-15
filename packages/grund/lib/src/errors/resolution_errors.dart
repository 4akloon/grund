import '../di/key.dart';
import 'grund_error.dart';

/// A failure while creating or releasing values.
sealed class ResolutionError extends GrundError {
  /// Creates the error.
  const ResolutionError();
}

/// An asynchronous binding was asked for before it was ready.
final class AsyncProviderNotReadyError extends ResolutionError {
  /// Creates the error for [key] owned by [module].
  const AsyncProviderNotReadyError({
    required this.key,
    required this.module,
    required this.chain,
  });

  /// The key that is not ready.
  final Key<Object> key;

  /// The module that owns it.
  final String module;

  /// The keys being created at the time, innermost first.
  final List<Key<Object>> chain;

  @override
  String get message =>
      '$key of module $module is asynchronous and not created yet. Only '
      'singletons may be asynchronous, and they must be declared in '
      'dependsOn so that they are created first.';
}

/// A factory threw.
final class ProviderCreationError extends ResolutionError {
  /// Creates the error for [key] owned by [module].
  const ProviderCreationError({
    required this.key,
    required this.module,
    required this.chain,
    required this.error,
    required this.stackTrace,
  });

  /// The key whose factory failed.
  final Key<Object> key;

  /// The module that owns it.
  final String module;

  /// The keys being created at the time, innermost first.
  final List<Key<Object>> chain;

  /// What the factory threw.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String get message {
    final via = chain.isEmpty ? '' : ' (required by ${chain.join(' <- ')})';
    return 'Creating $key of module $module failed$via: $error';
  }
}

/// A call-scoped binding was resolved outside a call.
final class ScopedOutsideCallError extends ResolutionError {
  /// Creates the error for [key] owned by [module].
  const ScopedOutsideCallError({required this.key, required this.module});

  /// The call-scoped key.
  final Key<Object> key;

  /// The module that owns it.
  final String module;

  @override
  String get message =>
      '$key of module $module is call-scoped and can only be resolved inside '
      'a call (Injector.openCall, or the context of a request).';
}

/// A module lifecycle method threw.
final class ModuleLifecycleError extends ResolutionError {
  /// Creates the error for [phase] of [module].
  const ModuleLifecycleError({
    required this.module,
    required this.phase,
    required this.error,
    required this.stackTrace,
  });

  /// The module.
  final String module;

  /// `onInit`.
  final String phase;

  /// What was thrown.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String get message => '$phase of module $module failed: $error';
}

/// One step that failed while shutting down.
typedef ShutdownFailure = ({String step, Object error, StackTrace stackTrace});

/// Some shutdown steps failed; all of them were still tried.
final class ShutdownError extends ResolutionError {
  /// Creates the error for [failures].
  const ShutdownError(this.failures);

  /// The failed steps in the order they ran.
  final List<ShutdownFailure> failures;

  @override
  String get message =>
      'Shutdown failed in ${failures.length} step(s): ${[for (final f in failures) '${f.step}: ${f.error}'].join('; ')}';
}

/// A startup failed and undoing it failed too.
final class StartupRollbackError extends ResolutionError {
  /// Creates the error for [cause] and the [failures] of the rollback.
  const StartupRollbackError({
    required this.cause,
    required this.causeStackTrace,
    required this.failures,
  });

  /// The failure that stopped the startup.
  final Object cause;

  /// Where [cause] was thrown.
  final StackTrace causeStackTrace;

  /// The steps of the rollback that failed.
  final List<ShutdownFailure> failures;

  @override
  String get message =>
      'Startup failed: $cause. Undoing it failed in ${failures.length} '
      'step(s): ${[for (final f in failures) '${f.step}: ${f.error}'].join('; ')}';
}
