import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../generate/generation_report.dart';
import '../generate/write_outcome.dart';
import '../package/package_root.dart';
import 'app_launcher.dart';
import 'app_process.dart';
import 'dev_printer.dart';
import 'reload_client.dart';
import 'reload_result.dart';
import 'shape_tracker.dart';

/// Runs the application of a package for `dev` and applies every
/// generation run to it: a hot reload when the change allows it, a hot
/// restart when it does not, nothing while the sources have problems.
///
/// The application never restarts on its own: when it exits, it starts
/// again after the next change. Operations run one at a time, in the order
/// they were asked for.
final class DevSession {
  /// Creates the session for [target] (absolute) of [package], started
  /// with [arguments], printing through [printer] and forwarding the
  /// application's output to [out] and [err].
  DevSession(
    this.package, {
    required this.target,
    required this.arguments,
    required this.printer,
    required this.out,
  }) : err = printer.err;

  /// The package of the application.
  final PackageRoot package;

  /// The absolute path of the entry point.
  final String target;

  /// The arguments of the application's `main`.
  final List<String> arguments;

  /// Prints what happens to the application.
  final DevPrinter printer;

  /// Where the application's stdout goes.
  final StringSink out;

  /// Where the application's stderr goes.
  final StringSink err;

  /// Starts the processes; replaced by tests only.
  AppLauncher launcher = const AppLauncher();

  final _shapes = ShapeTracker();
  Future<void> _tail = Future<void>.value();
  final _unapplied = <String>{};
  _Running? _running;
  var _stopped = false;

  /// Applies the generation run [report] for the [changed] paths: starts
  /// the application when it is not running, restarts it when a file
  /// changed its shape (see [ShapeTracker]), reloads it otherwise.
  Future<void> apply(List<String> changed, GenerationReport report) =>
      _live(() => _apply(changed, report));

  /// Reloads the application now (the `r` key); starts it when it is not
  /// running.
  Future<void> reload() => _live(() async {
    final running = _running;
    if (running == null) return _launch();
    await _reload(running);
  });

  /// Restarts the application now (the `R` key).
  Future<void> restart() => _live(() => _restart('restart requested'));

  /// Stops the application: its dartnest applications close (requests in
  /// flight finish), then the process ends.
  Future<void> stop() {
    // Final at once: operations already queued must not start it again.
    _stopped = true;
    return _serially(_shutdown);
  }

  // Every operation runs after the previous one, also after one that
  // failed: its failure went to its own caller, and stop() must still end
  // the process.
  Future<void> _serially(Future<void> Function() operation) => _tail = _tail
      .then((_) => operation(), onError: (Object _) => operation());

  // Operations other than the stop itself do nothing after stop().
  Future<void> _live(Future<void> Function() operation) =>
      _serially(() => _stopped ? Future<void>.value() : operation());

  Future<void> _apply(List<String> changed, GenerationReport report) async {
    final running = _running;
    // A shape change in a run with problems is applied by the next clean
    // run, whichever files that one lists.
    _unapplied.addAll(changed);
    if (report.hasProblems) {
      printer.waiting(isRunning: running != null);
      return;
    }
    if (report.outcome == WriteOutcome.written ||
        report.outcome == WriteOutcome.deleted) {
      _unapplied.add(package.outputPath);
    }
    final reshaped = _shapes.changed(_unapplied);
    _unapplied.clear();
    if (running == null) return _launch();
    if (reshaped.isEmpty) return _reload(running);
    await _restart(
      '${package.display(reshaped.first)} changed a field, a constructor '
      'or a top-level variable',
    );
  }

  Future<void> _reload(_Running running) async {
    final result = await running.client.reload();
    // The application died meanwhile and said so; its reload result is moot.
    if (!identical(_running, running)) return;
    printer.reloaded(result);
    if (result is ReloadRejected) await _replace();
  }

  Future<void> _restart(String reason) async {
    printer.restarting(reason);
    await _replace();
  }

  Future<void> _replace() async {
    await _shutdown();
    await _launch();
  }

  Future<void> _launch() async {
    if (_stopped) return;
    _shapes.remember(_sources());
    final process = await launcher.start(
      target: target,
      arguments: arguments,
      workingDirectory: package.path,
      out: out,
      err: err,
    );
    final uri = await process.serviceUri;
    final client = uri == null ? null : await _connect(process, uri);
    if (uri == null || client == null) {
      final code = await process.stop();
      if (uri == null) {
        printer.exited(code);
      } else {
        printer.unreachable();
      }
      return;
    }
    final running = _Running(process, client);
    _running = running;
    printer.started(process.pid, uri);
    unawaited(process.exitCode.then((code) => _exited(running, code)));
  }

  Future<ReloadClient?> _connect(AppProcess process, Uri uri) async {
    try {
      return await launcher.connect(uri);
    } catch (_) {
      await process.stop();
      rethrow;
    }
  }

  void _exited(_Running running, int code) {
    if (!identical(_running, running)) return;
    _running = null;
    running.client.dispose().ignore();
    printer.exited(code);
  }

  Future<void> _shutdown() async {
    final running = _running;
    if (running == null) return;
    _running = null;
    try {
      await launcher.close(running.client);
    } finally {
      try {
        await running.process.stop();
      } finally {
        await running.client.dispose();
      }
    }
  }

  /// The Dart files the application is built from, as far as `dev`
  /// watches them: `lib/` and the directory of the entry point.
  List<String> _sources() => [
    for (final directory in {package.libPath, p.dirname(target)})
      ..._dartFiles(directory),
  ];

  static Iterable<String> _dartFiles(String directory) =>
      Directory(directory).existsSync()
      ? Directory(directory)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.endsWith('.dart'))
      : const <String>[];
}

/// The application process with its VM service connection.
final class _Running {
  _Running(this.process, this.client);

  final AppProcess process;
  final ReloadClient client;
}
