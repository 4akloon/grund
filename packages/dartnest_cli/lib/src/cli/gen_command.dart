import 'package:args/command_runner.dart';

import '../generate/generation_session.dart';
import '../package/package_root.dart';
import 'cli_exit_code.dart';
import 'dartnest_cli.dart';
import 'report_printer.dart';

/// `gen`: writes `lib/<package>.dartnest.dart` from the annotations of
/// `lib/`.
final class GenCommand extends Command<int> {
  /// Creates the command of [cli].
  GenCommand(this.cli) {
    argParser.addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      valueHelp: 'path',
      help: 'The package to generate.',
    );
  }

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'gen';

  @override
  String get description =>
      'Generates lib/<package>.dartnest.dart from the annotations in lib/.';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('gen was not parsed.'));
    if (options.rest.isNotEmpty) {
      usageException('gen takes no positional arguments.');
    }
    final package = PackageRoot.open(options.option('directory') ?? '.');
    final session = GenerationSession(package, generator: cli.generator);
    try {
      final report = await session.run();
      ReportPrinter(cli.out, cli.err).report(report);
      return report.hasProblems
          ? CliExitCode.problems.code
          : CliExitCode.success.code;
    } finally {
      await session.close();
    }
  }
}
