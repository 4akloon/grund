import 'package:args/command_runner.dart';
import 'package:watcher/watcher.dart';

import '../generate/generation_session.dart';
import '../package/package_root.dart';
import '../watch/watch_loop.dart';
import 'cli_exit_code.dart';
import 'dartnest_cli.dart';
import 'report_printer.dart';

/// `gen`: writes `lib/<package>.dartnest.dart` from the annotations of
/// `lib/`, once or on every change (`--watch`).
final class GenCommand extends Command<int> {
  /// Creates the command of [cli].
  GenCommand(this.cli) {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        valueHelp: 'path',
        help: 'The package to generate.',
      )
      ..addFlag(
        'watch',
        abbr: 'w',
        negatable: false,
        help: 'Regenerate on every change of lib/ until Ctrl+C.',
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
    final printer = ReportPrinter(cli.out, cli.err);
    try {
      return options.flag('watch')
          ? await _watch(session, printer)
          : await _once(session, printer);
    } finally {
      await session.close();
    }
  }

  Future<int> _once(GenerationSession session, ReportPrinter printer) async {
    final report = await session.run();
    printer.report(report);
    return report.hasProblems
        ? CliExitCode.problems.code
        : CliExitCode.success.code;
  }

  Future<int> _watch(GenerationSession session, ReportPrinter printer) async {
    final watcher = DirectoryWatcher(session.package.libPath);
    await WatchLoop(session, printer).run(watcher, cli.untilStopped());
    return CliExitCode.success.code;
  }
}
