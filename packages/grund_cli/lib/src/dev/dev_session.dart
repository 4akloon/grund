import 'dart:async';

import 'package:path/path.dart' as p;

import '../generate/generation_report.dart';
import 'app_launcher.dart';
import 'app_process.dart';
import 'dev_printer.dart';
import 'dev_target.dart';
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
  /// Creates the session for [target], printing through [printer] and
  /// forwarding the application's stdout to [out] and its stderr to the
  /// printer's error sink. The application is started and reached through
  /// [launcher] (tests replace it to make these steps fail).
  DevSession(
    this.target, {
    required this.printer,
    required this.out,
    this.launcher = const AppLauncher(),
  });

  /// What runs: the entry point, its package and its arguments.
  final DevTarget target;

  /// Prints what happens to the application.
  final DevPrinter printer;

  /// Where the application's stdout goes.
  final StringSink out;

  /// Starts the processes and connects to them.
  final AppLauncher launcher;

  final _shapes = ShapeTracker();
  Future<void> _tail = Future<void>.value();
  final _unapplied = <String>{};
  _Running? _running;
  // Every process not yet exited, also one still starting or stopping.
  final _processes = <AppProcess>{};
  var _stopped = false;
  // Whether the last generation run found problems.
  var _hasProblems = false;

  /// Applies the generation run [report] for the [changed] paths: starts
  /// the application when it is not running, restarts it when a file
  /// changed its shape (see [ShapeTracker]), reloads it otherwise.
  Future<void> apply(List<String> changed, GenerationReport report) =>
      _live(() => _apply(changed, report));

  /// Applies what is still waiting (the `r` key): starts the application
  /// when it is not running, restarts it when a change held back by
  /// problems changed a shape, reloads it otherwise.
  Future<void> reload() => _live(() {
    // Nothing is reloaded or restarted into sources that do not compile.
    if (!_hasProblems) return _applyPending(_running);
    printer.waiting(isRunning: _running != null);
    return Future<void>.value();
  });

  /// Restarts the application now (the `R` key).
  Future<void> restart() => _live(() => _restart('restart requested'));

  /// Stops the application: its grund applications close (requests in
  /// flight finish), then the process ends.
  Future<void> stop() {
    // Final at once: operations already queued must not start it again.
    _stopped = true;
    return _serially(_shutdown);
  }

  /// Ends the application process at once, without closing anything; for
  /// the forced exit after a second interrupt.
  void kill() {
    _stopped = true;
    for (final process in _processes) {
      process.kill();
    }
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
    // A shape change in a run with problems is applied by the next clean
    // run (or by `r`), whichever files that one lists.
    _unapplied.addAll(changed);
    _hasProblems = report.hasProblems;
    if (report.hasProblems) {
      printer.waiting(isRunning: _running != null);
      return;
    }
    _unapplied.addAll([
      for (final file in report.changedFiles) p.join(target.package.path, file),
    ]);
    await _applyPending(_running);
  }

  // The changes are forgotten only once they were applied: a failed
  // launch or reload leaves them for the next attempt.
  Future<void> _applyPending(_Running? running) async {
    if (running == null) {
      await _launch();
    } else {
      final reshaped = _shapes.changed(_unapplied);
      if (reshaped.isEmpty) {
        await _reload(running);
      } else {
        await _restart(
          '${target.package.display(reshaped.first)} changed a field, a '
          'constructor or a top-level variable',
        );
      }
    }
    _unapplied.clear();
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
    _shapes.remember(target.sources());
    final process = await launcher.start(
      target.command,
      out: out,
      err: printer.err,
    );
    _processes.add(process);
    // A kill() while the process was starting has not seen it.
    if (_stopped) process.kill();
    unawaited(process.exitCode.then((_) => _processes.remove(process)));
    var timedOut = false;
    final uri = await process.serviceUri.timeout(
      launcher.timeouts.serviceUri,
      onTimeout: () {
        timedOut = true;
        return null;
      },
    );
    final client = uri == null ? null : await _connect(process, uri);
    if (uri == null || client == null) {
      final code = await process.stop();
      if (uri == null && !timedOut) {
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
    var succeeded = false;
    try {
      final client = await launcher.connect(uri);
      succeeded = true;
      return client;
    } finally {
      // The failure itself propagates; the process must not outlive it.
      if (!succeeded) await process.stop();
    }
  }

  void _exited(_Running running, int code) {
    // After a stop the process ends with the terminal's Ctrl+C or our
    // SIGTERM; that is not news.
    if (_stopped || !identical(_running, running)) return;
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
}

/// The application process with its VM service connection.
final class _Running {
  _Running(this.process, this.client);

  final AppProcess process;
  final ReloadClient client;
}
