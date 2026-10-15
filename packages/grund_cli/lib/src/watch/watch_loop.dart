import 'dart:async';
import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../cli/cli_failure.dart';
import '../cli/report_printer.dart';
import '../generate/generated_outputs.dart';
import '../generate/generation_report.dart';
import '../generate/generation_session.dart';

/// Regenerates a package whenever its `lib/` changes, until stopped.
///
/// Events are debounced: a burst (an editor saving through a temporary
/// file, a branch switch) gives one run with every changed path. Runs never
/// overlap; paths that change during a run are collected into exactly one
/// follow-up run. Non-Dart files and files named like the session's own
/// output (`*.g.dart`) are ignored. The name alone
/// decides, not the header: the watcher gets events synchronously and must
/// not read a file that is being replaced, and the session's own writes
/// would otherwise start a run after every run. The price is that editing
/// a hand-written file with such a name starts no run. A [CliFailure] of a
/// run is printed and watching goes on; any other failure of a run ends [run] with
/// it at once, and so does an error of the watcher's event stream (OP8):
/// the `finally` of [run] still stops the run in flight, so whoever started
/// the loop can clean up (`dev` stops the application and restores the
/// terminal).
final class WatchLoop {
  /// Creates the loop over [session], printing through [printer].
  WatchLoop(
    GenerationSession session,
    ReportPrinter printer, {
    Duration debounce = defaultDebounce,
  }) : this.custom(
         generate: (changed) => session.run(changed: changed),
         watched: session.package.display(session.package.libPath),
         printer: printer,
         debounce: debounce,
       );

  /// Creates the loop over any [generate] (the run of a session), printing
  /// [watched] as the watched directories and calling [afterRun] after
  /// each printed run; for `dev` and for tests that control the runs.
  WatchLoop.custom({
    required this.generate,
    required this.watched,
    required this.printer,
    this.afterRun,
    this.debounce = defaultDebounce,
  });

  /// How long the loop waits after the last event before it runs.
  static const defaultDebounce = Duration(milliseconds: 100);

  /// Runs the generation for the changed absolute paths.
  final Future<GenerationReport> Function(List<String> changed) generate;

  /// The watched directories as printed after the first run (`lib`).
  final String watched;

  /// Called with the changed paths and the report of every run, after the
  /// report is printed and before the next run starts; not called when a
  /// run fails with a [CliFailure]. Any failure of [afterRun], a
  /// [CliFailure] included, ends [run]; unlike a [CliFailure] of [generate],
  /// which is printed while watching goes on.
  final Future<void> Function(List<String> changed, GenerationReport report)?
  afterRun;

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
    final subscription = watcher.events
        .where(_isSource)
        .listen(_add, onError: _fail);
    try {
      await watcher.ready;
      _start(_first);
      await Future.any([stop, _failure.future]);
    } finally {
      _stopped = true;
      _timer?.cancel();
      await subscription.cancel();
      await _active;
    }
    if (_failure.isCompleted) await _failure.future;
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
        _fail(error, trace);
      },
    );
  }

  void _fail(Object error, StackTrace trace) {
    if (!_failure.isCompleted) _failure.completeError(error, trace);
  }

  Future<void> _first() async {
    await _generate(const []);
    printer.watching(watched);
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
    final GenerationReport report;
    try {
      report = await generate(changed);
    } on CliFailure catch (failure) {
      printer.err.writeln(failure.message);
      return;
    }
    printer.report(report);
    await afterRun?.call(changed, report);
  }

  static bool _isSource(WatchEvent event) =>
      event.path.endsWith('.dart') &&
      !GeneratedOutputs.hasGeneratedName(event.path);
}
