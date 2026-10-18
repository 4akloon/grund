/// What one `dart compile js` run produced.
final class CompileOutcome {
  /// Creates the outcome of a run that exited with [exitCode] and printed
  /// [output] (stdout and stderr).
  const CompileOutcome(this.exitCode, this.output);

  /// The exit code of the compiler.
  final int exitCode;

  /// Everything the compiler printed.
  final String output;

  /// Whether the compiler succeeded.
  bool get succeeded => exitCode == 0;
}
