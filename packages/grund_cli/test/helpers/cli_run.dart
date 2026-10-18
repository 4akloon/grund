import 'package:grund_cli/grund_cli.dart';

/// One in-process run of [GrundCli] with what it printed.
final class CliRun {
  CliRun._(this.exitCode, this.out, this.err);

  /// Runs `grund_cli` with [arguments].
  ///
  /// `bundle` compiles with [compileRunner] when given.
  static Future<CliRun> run(
    List<String> arguments, {
    CompileRunner? compileRunner,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await GrundCli(
      out: out,
      err: err,
      compileRunner: compileRunner ?? const ProcessCompileRunner(),
    ).run(arguments);
    return CliRun._(code, '$out', '$err');
  }

  /// The exit code.
  final int exitCode;

  /// What went to stdout.
  final String out;

  /// What went to stderr.
  final String err;
}
