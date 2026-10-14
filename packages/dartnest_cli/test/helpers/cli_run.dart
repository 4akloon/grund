import 'package:dartnest_cli/dartnest_cli.dart';

/// One in-process run of [DartnestCli] with what it printed.
final class CliRun {
  CliRun._(this.exitCode, this.out, this.err);

  /// Runs `dartnest_cli` with [arguments].
  static Future<CliRun> run(List<String> arguments) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await DartnestCli(out: out, err: err).run(arguments);
    return CliRun._(code, '$out', '$err');
  }

  /// The exit code.
  final int exitCode;

  /// What went to stdout.
  final String out;

  /// What went to stderr.
  final String err;
}
