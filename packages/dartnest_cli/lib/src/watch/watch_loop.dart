import 'dart:async';
import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../cli/cli_failure.dart';
import '../cli/report_printer.dart';
import '../generate/generation_report.dart';
import '../generate/generation_session.dart';

/// Regenerates a package whenever its `lib/` changes, until stopped.
///
/// Events are debounced: a burst (an editor saving through a temporary
/// file, a branch switch) gives one run with every changed path. Runs never
/// overlap; paths that change during a run are collected into exactly one
/// follow-up run. Generated `*.dartnest.dart` files (the session's own
/// output) and non-Dart files are ignored. A [CliFailure] of a run is
/// printed and watching goes on; any other failure of a run ends [run] with
/// it at once. Errors of the watcher's event stream are not handled and end
/// the process (OP8).
final class WatchLoop {
  /// Creates the loop over [session], printing through [printer].
  WatchLoop(
    GenerationSession session,
    ReportPrinter printer, {
    Duration debounce = defaultDebounce,
  }) : this.custom(
         generate: (changed) => session.run(changed: changed),
         display: session.package.display,
         printer: printer,
         debounce: debounce,
       );

  /// Creates the loop over any [generate] (the run of a session) and
  /// [display] (a path relative to the package root); for tests that need
  /// to control the runs.
  WatchLoop.custom({
    required this.generate,
    required this.display,
    required this.printer,
    this.debounce = defaultDebounce,
  });

  /// How long the loop waits after the last event before it runs.
  static const defaultDebounce = Duration(milliseconds: 100);

  /// Runs the generation for the changed absolute paths.
  final Future<GenerationReport> Function(List<String> changed) generate;

  /// Shortens an absolute path to one relative to the package root.
  final String Function(String path) display;

  /// Prints every run.
  final ReportPrinter printer;

  /// The quiet time after the last event that starts a run.
  final Duration debounce;

  final _pending = SplayTreeSet<String>();
  final _failure = Completer<void>();
  Timer? _timer;
  Future<void>? _active;
  var _stopped = false;

  /// Generates once, then once per batch of [watcher] events, until [stop]
  /// completes; returns when the run in flight has finished.
  ///
  /// Completes with the error of a run that failed with anything but a
  /// [CliFailure], without waiting for [stop]. Changes still waiting for
  /// their debounce or their turn when [stop] completes are dropped.
  Future<void> run(Watcher watcher, Future<void> stop) async {
    final subscription = watcher.events.where(_isSource).listen(_add);
    try {
      await watcher.ready;
      _start(() => _first(watcher));
      await Future.any([stop, _failure.future]);
    } finally {
      _stopped = true;
      _timer?.cancel();
      await subscription.cancel();
      await _active;
    }
  }

  void _add(WatchEvent event) {
    _pending.add(p.normalize(p.absolute(event.path)));
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    if (_active == null) _start(_drain);
  }

  void _start(Future<void> Function() work) {
    _active = work().then<void>(
      (_) => _active = null,
      onError: (Object error, StackTrace trace) {
        _active = null;
        if (!_failure.isCompleted) _failure.completeError(error, trace);
      },
    );
  }

  Future<void> _first(Watcher watcher) async {
    await _generate(const []);
    printer.watching(display(watcher.path));
    await _drain();
  }

  Future<void> _drain() async {
    while (!_stopped && _pending.isNotEmpty) {
      final changed = _pending.toList();
      _pending.clear();
      await _generate(changed);
    }
  }

  Future<void> _generate(List<String> changed) async {
    try {
      printer.report(await generate(changed));
    } on CliFailure catch (failure) {
      printer.err.writeln(failure.message);
    }
  }

  static bool _isSource(WatchEvent event) =>
      event.path.endsWith('.dart') && !event.path.endsWith('.dartnest.dart');
}
