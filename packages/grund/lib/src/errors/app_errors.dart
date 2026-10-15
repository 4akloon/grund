import 'grund_error.dart';

/// A failure of the application as a whole.
sealed class AppError extends GrundError {
  /// Creates the error.
  const AppError();
}

/// An operation was attempted in a state that does not allow it.
final class ApplicationStateError extends AppError {
  /// Creates the error for [operation] refused because of [reason].
  const ApplicationStateError({required this.operation, required this.reason});

  /// What was attempted.
  final String operation;

  /// Why it cannot be done now.
  final String reason;

  @override
  String get message => 'Cannot $operation: $reason.';
}

/// `only` names runners the graph does not provide.
final class UnknownRunnerError extends AppError {
  /// Creates the error for the [unknown] names.
  const UnknownRunnerError({required this.unknown, required this.available});

  /// The names that match no runner.
  final List<String> unknown;

  /// The runners the graph provides, sorted.
  final List<String> available;

  @override
  String get message =>
      'Unknown runner(s): ${unknown.join(', ')}. The graph provides: '
      '${available.isEmpty ? 'none' : available.join(', ')}.';
}

/// Two runners of the graph answer to the same name.
final class DuplicateRunnerError extends AppError {
  /// Creates the error for the [name] that is taken twice.
  const DuplicateRunnerError(this.name);

  /// The name two runners share.
  final String name;

  @override
  String get message =>
      'Two runners are named "$name"; `only` could not tell them apart. '
      'Give each runner its own name.';
}

/// A runner failed in one of its phases.
final class RunnerError extends AppError {
  /// Creates the error for [phase] of [runner].
  const RunnerError({
    required this.runner,
    required this.phase,
    required this.error,
    required this.stackTrace,
  });

  /// The runner's name.
  final String runner;

  /// `prepare`, `start`, `stop` or `reassemble`.
  final String phase;

  /// What the runner threw.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String get message => 'Runner "$runner" failed to $phase: $error';
}
