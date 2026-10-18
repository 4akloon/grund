import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../dev/dev_bundle.dart';
import '../bundle/client_bundler.dart';
import '../dev/dev_session.dart';
import '../dev/dev_target.dart';
import '../dev/live_reload_hub.dart';
import '../dev/live_reload_start.dart';
import '../dev/terminal_keys.dart';
import '../generate/generation_session.dart';
import '../package/package_root.dart';
import '../watch/watch_loop.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'dev_wiring.dart';
import 'grund_cli.dart';

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
      )
      ..addOption(
        'client-entry',
        defaultsTo: ClientBundler.defaultEntry,
        valueHelp: 'file',
        help:
            'The browser entry point, relative to the package; bundled '
            'when it exists.',
      )
      ..addOption(
        'output',
        defaultsTo: ClientBundler.defaultOutputDirectory,
        valueHelp: 'dir',
        help: 'Where the client bundle goes, relative to the package.',
      );
  }

  /// The entry point when no `--target` is given.
  static const defaultTarget = 'bin/main.dart';

  /// The command line this command belongs to.
  final GrundCli cli;

  @override
  String get name => 'dev';

  @override
  String get description =>
      'Runs the application and hot reloads it on every change.\n'
      'In a terminal, r reloads and R restarts it now.';

  @override
  String get invocation => 'grund_cli dev [options] [-- <arguments of main>]';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('dev was not parsed.'));
    final package = PackageRoot.open(options.option('directory') ?? '.');
    final target = _target(package, options.option('target') ?? '');
    // Open pages reconnect to the same endpoint across restarts; it ends
    // with dev.
    final liveReload = await LiveReloadStart.run(LiveReloadHub.start);
    try {
      await _serve(
        package,
        target,
        options.rest,
        liveReload,
        DevWiring(cli).bundle(package, options),
      );
    } finally {
      await liveReload.close();
    }
    return CliExitCode.success.code;
  }

  Future<void> _serve(
    PackageRoot package,
    String target,
    List<String> arguments,
    LiveReloadHub liveReload,
    DevBundle? bundle,
  ) async {
    final wiring = DevWiring(cli);
    final session = GenerationSession(package, generator: cli.generator);
    final dev = wiring.session(
      DevTarget(
        package,
        entry: target,
        arguments: arguments,
        environment: liveReload.environment,
      ),
      liveReload,
      bundle,
    );
    final failure = Completer<void>();
    final keys = cli.host.keys().listen((key) => _press(dev, key, failure));
    final (:stopped, :subscription) = cli.host.interruption.listen(
      _forceOnSecond(dev, failure.future),
    );
    // Stopping the session at the interrupt itself, not after the watch
    // loop ended: the terminal's Ctrl+C reaches the application too, and its
    // exit must not be reported as a crash.
    final stop = Future.any([stopped.whenComplete(dev.stop), failure.future]);
    try {
      await bundle?.initial();
      final (watcher, loop) = wiring.watchLoop(
        package,
        target,
        session,
        dev,
        bundle,
      );
      await _run(loop, watcher, session, dev, stop);
    } finally {
      try {
        await keys.cancel();
      } finally {
        // A signal listener keeps the VM alive: it goes even when the
        // cleanup above throws.
        await subscription.cancel();
      }
    }
  }

  Future<void> _run(
    WatchLoop loop,
    Watcher watcher,
    GenerationSession session,
    DevSession dev,
    Future<void> stop,
  ) async {
    try {
      await loop.run(watcher, stop);
    } on CliFailure {
      rethrow;
    } on Exception catch (error) {
      // Anything a run, the application process or a key action failed
      // with (an Error is a bug and stays loud) ends dev with a message
      // and the software exit code, not an unmapped exception.
      throw CliFailure(CliExitCode.software, 'dev stopped: $error');
    } finally {
      await dev.stop();
      await session.close();
    }
  }

  /// What `dev` does with the interrupt number `received`: the first stops
  /// it (through [Interruption.listen]'s `stopped`) and takes `SIGINT`'s
  /// default away, so that a second one, while the application is still
  /// closing, can end the process at once instead of killing it half-way
  /// (child orphaned, terminal left in raw mode): kill the child, restore
  /// the terminal, exit 130. An interrupt after a failed key action
  /// ([failure]) counts as the second, since `dev` is shutting down already.
  void Function(int) _forceOnSecond(DevSession dev, Future<void> failure) {
    var failed = false;
    unawaited(failure.then((_) {}, onError: (Object _) => failed = true));
    return (received) {
      if (received < 2 && !failed) return;
      dev.kill();
      TerminalKeys.restore();
      cli.host.interruption.forceExit(CliExitCode.interrupted.code);
    };
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
