import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../dev/dev_printer.dart';
import '../dev/dev_session.dart';
import '../dev/merged_watcher.dart';
import '../generate/generation_session.dart';
import '../package/package_root.dart';
import '../watch/watch_loop.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'dartnest_cli.dart';
import 'report_printer.dart';

/// `dev`: runs the application and, on every change of `lib/` or of the
/// directory of its entry point, generates the package and hot reloads the
/// application, or hot restarts it when a reload cannot apply the change.
final class DevCommand extends Command<int> {
  /// Creates the command of [cli].
  DevCommand(this.cli) {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        valueHelp: 'path',
        help: 'The package of the application.',
      )
      ..addOption(
        'target',
        abbr: 't',
        aliases: ['entry'],
        defaultsTo: defaultTarget,
        valueHelp: 'path',
        help: 'The entry point, relative to the package.',
      );
  }

  /// The entry point when no `--target` is given.
  static const defaultTarget = 'bin/main.dart';

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'dev';

  @override
  String get description =>
      'Runs the application and hot reloads it on every change.';

  @override
  String get invocation =>
      'dartnest_cli dev [options] [-- <arguments of main>]';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('dev was not parsed.'));
    final package = PackageRoot.open(options.option('directory') ?? '.');
    final target = _target(package, options.option('target') ?? '');
    final session = GenerationSession(package, generator: cli.generator);
    final dev = DevSession(
      package,
      target: target,
      arguments: options.rest,
      printer: DevPrinter(package.display(target), cli.out, cli.err),
      out: cli.out,
    );
    final failure = Completer<void>();
    final keys = cli.keys().listen((key) => _press(dev, key, failure));
    try {
      final (watcher, watched) = _watch(package, target);
      await WatchLoop.custom(
        generate: (changed) => session.run(changed: changed),
        watched: watched,
        printer: ReportPrinter(cli.out, cli.err),
        afterRun: dev.apply,
      ).run(watcher, Future.any([cli.untilStopped(), failure.future]));
    } finally {
      await keys.cancel();
      await dev.stop();
      await session.close();
    }
    return CliExitCode.success.code;
  }

  static String _target(PackageRoot package, String relative) {
    final target = p.normalize(p.join(package.path, relative));
    if (!p.isWithin(package.path, p.dirname(target))) {
      throw CliFailure(
        CliExitCode.usage,
        'The entry point must be in a directory of the package, such as '
        'bin/; $relative is not.',
      );
    }
    if (File(target).existsSync()) return target;
    throw CliFailure(
      CliExitCode.noInput,
      'No $relative in ${package.path}; pass the entry point with --target.',
    );
  }

  /// The watcher of `lib/` and of the directory of [target], and how the
  /// watched directories are printed.
  static (Watcher, String) _watch(PackageRoot package, String target) {
    final lib = DirectoryWatcher(package.libPath);
    if (p.isWithin(package.libPath, target)) return (lib, 'lib');
    final directory = p.dirname(target);
    return (
      MergedWatcher(package.path, [lib, DirectoryWatcher(directory)]),
      'lib/ and ${package.display(directory)}',
    );
  }

  /// Runs the operation of [key]; a failure of it ends `dev` through
  /// [failure].
  static void _press(DevSession dev, String key, Completer<void> failure) {
    final operation = switch (key) {
      'r' => dev.reload,
      'R' => dev.restart,
      _ => null,
    };
    unawaited(
      operation?.call().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!failure.isCompleted) failure.completeError(error, stackTrace);
        },
      ),
    );
  }
}
