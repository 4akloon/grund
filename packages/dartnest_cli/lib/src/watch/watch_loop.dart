import 'dart:async';
import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../cli/cli_failure.dart';
import '../cli/report_printer.dart';
import '../generate/generation_session.dart';

/// Regenerates a package whenever its `lib/` changes, until stopped.
///
/// Events are debounced: a burst (an editor saving through a temporary
/// file, a branch switch) gives one run with every changed path. Runs never
/// overlap; changes during a run go into the next one. Generated
/// `*.dartnest.dart` files (the session's own output) and non-Dart files
/// are ignored. A [CliFailure] of a run is printed and watching goes on;
/// any other failure ends the process.
final class WatchLoop {
  /// Creates the loop over [session], printing through [printer].
  WatchLoop(this.session, this.printer, {this.debounce = defaultDebounce});

  /// How long the loop waits after the last event before it runs.
  static const defaultDebounce = Duration(milliseconds: 100);

  /// The generation that runs.
  final GenerationSession session;

  /// Prints every run.
  final ReportPrinter printer;

  /// The quiet time after the last event that starts a run.
  final Duration debounce;

  final _pending = SplayTreeSet<String>();
  Timer? _timer;
  Future<void> _runs = Future.value();

  /// Generates once, then once per batch of [watcher] events, until [stop]
  /// completes; returns when the last run has finished.
  Future<void> run(Watcher watcher, Future<void> stop) async {
    final subscription = watcher.events.where(_isSource).listen(_add);
    await watcher.ready;
    _runs = _generate(
      const [],
    ).then((_) => printer.watching(session.package.display(watcher.path)));
    await stop;
    await subscription.cancel();
    _timer?.cancel();
    await _runs;
  }

  void _add(WatchEvent event) {
    _pending.add(p.normalize(p.absolute(event.path)));
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    final changed = _pending.toList();
    _pending.clear();
    _runs = _runs.then((_) => _generate(changed));
  }

  Future<void> _generate(List<String> changed) async {
    try {
      printer.report(await session.run(changed: changed));
    } on CliFailure catch (failure) {
      printer.err.writeln(failure.message);
    }
  }

  static bool _isSource(WatchEvent event) =>
      event.path.endsWith('.dart') && !event.path.endsWith('.dartnest.dart');
}
