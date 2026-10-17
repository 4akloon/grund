import 'grund_error.dart';

/// A failure to read an environment variable.
sealed class EnvironmentError extends GrundError {
  /// Creates the error.
  const EnvironmentError();

  /// The name of the variable.
  String get name;
}

/// A required variable is not set.
final class MissingVariableError extends EnvironmentError {
  /// Creates the error for the variable [name].
  const MissingVariableError(this.name);

  @override
  final String name;

  @override
  String get message =>
      'The environment variable $name is not set. Set it, or read it with a '
      'fallback.';
}

/// A variable is set to a value of the wrong form; the value is not shown.
final class InvalidVariableError extends EnvironmentError {
  /// Creates the error for the variable [name], which must be [expected].
  const InvalidVariableError({required this.name, required this.expected});

  @override
  final String name;

  /// What the value must be, such as "an integer from 0 to 65535".
  final String expected;

  @override
  String get message =>
      'The environment variable $name must be $expected. Its value is not '
      'shown, as it may be a secret.';
}
