import 'cli_exit_code.dart';

/// A failure that ends a command: [message] goes to stderr and the process
/// exits with [exitCode].
final class CliFailure implements Exception {
  /// Creates the failure.
  const CliFailure(this.exitCode, this.message);

  /// How the process exits.
  final CliExitCode exitCode;

  /// One sentence for the user, naming the file and the fix.
  final String message;

  @override
  String toString() => message;
}
