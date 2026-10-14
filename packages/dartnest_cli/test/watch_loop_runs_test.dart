import 'dart:async';

import 'package:dartnest_cli/src/cli/cli_exit_code.dart';
import 'package:dartnest_cli/src/cli/cli_failure.dart';
import 'package:dartnest_cli/src/cli/report_printer.dart';
import 'package:dartnest_cli/src/generate/generation_report.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:dartnest_cli/src/watch/watch_loop.dart';
import 'package:test/test.dart';

import 'helpers/fake_watcher.dart';
import 'helpers/line_sink.dart';

const _debounce = Duration(milliseconds: 20);
const _gap = Duration(milliseconds: 60);

final _report = GenerationReport(
  output: 'lib/x.dartnest.dart',
  outcome: WriteOutcome.written,
  elapsed: Duration.zero,
);

/// A loop whose runs the test releases one by one.
final class _Harness {
  _Harness() {
    loop = WatchLoop.custom(
      generate: _generate,
      watched: 'lib',
      printer: ReportPrinter(lines, lines),
      afterRun: _afterRun,
      debounce: _debounce,
    );
    stop = Completer<void>();
    addTearDown(() {
      if (!stop.isCompleted) stop.complete();
    });
  }

  final lines = LineSink();
  final watcher = FakeWatcher('/pkg/lib');
  final calls = <List<String>>[];
  final _gates = <Completer<void>>[];
  Object? failWith;
  // Both are set in the constructor body, before any method reads them.
  late final WatchLoop loop;
  late final Completer<void> stop;

  /// Every run waits for [release] when [blocking] is set.
  bool blocking = false;

  Future<GenerationReport> _generate(List<String> changed) async {
    calls.add(changed);
    if (blocking) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    final failure = failWith;
    if (failure != null) throw failure;
    return _report;
  }

  /// Each call of `afterRun`: the changed paths and the last line printed
  /// before it.
  final afterRuns = <String>[];

  /// While set, `afterRun` waits for it.
  Completer<void>? afterGate;

  Future<void> _afterRun(List<String> changed, GenerationReport report) async {
    afterRuns.add('${changed.join(',')} after ${lines.lines.last}');
    await afterGate?.future;
  }

  Future<void> start() => loop.run(watcher, stop.future);

  Future<void> release() async {
    while (_gates.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    _gates.removeAt(0).complete();
  }

  Future<void> changed(String file) async {
    watcher.modify(file);
    await Future<void>.delayed(_gap);
  }
}

void main() {
  test('an error of the watcher ends the run and cleans up', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();

    h.watcher.error(StateError('watch failed'));

    await expectLater(
      done,
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'watch failed'),
      ),
    );
    expect(h.watcher.hasListener, isFalse);
  });

  test('paths changed while a run is in flight share one follow-up', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    h.blocking = true;

    await h.changed('/pkg/lib/a.dart');
    await h.changed('/pkg/lib/c.dart');
    await h.changed('/pkg/lib/b.dart');
    await h.changed('/pkg/lib/c.dart');
    h.blocking = false;
    await h.release();
    expect(await h.lines.next(), startsWith('Generated'));
    expect(await h.lines.next(), startsWith('Generated'));

    expect(await h.lines.after(_gap), isEmpty);
    expect(h.calls, [
      <String>[],
      ['/pkg/lib/a.dart'],
      ['/pkg/lib/b.dart', '/pkg/lib/c.dart'],
    ]);
    h.stop.complete();
    await done;
  });

  test('afterRun follows the printed report of every run', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();

    await h.changed('/pkg/lib/a.dart');
    await h.lines.next();
    h.stop.complete();
    await done;

    expect(h.afterRuns, [
      ' after Generated lib/x.dartnest.dart in 0 ms.',
      '/pkg/lib/a.dart after Generated lib/x.dartnest.dart in 0 ms.',
    ]);
  });

  test('the next run waits for afterRun to finish', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    final gate = h.afterGate = Completer<void>();

    await h.changed('/pkg/lib/a.dart');
    await h.lines.next();
    await h.changed('/pkg/lib/b.dart');
    expect(h.calls.length, 2);

    h.afterGate = null;
    gate.complete();
    expect(await h.lines.next(), startsWith('Generated'));
    h.stop.complete();
    await done;
    expect(h.calls.length, 3);
  });

  test('afterRun is not called for a run that failed to write', () async {
    final h = _Harness()
      ..failWith = const CliFailure(CliExitCode.cannotCreate, 'No write.');
    final done = h.start();

    expect(await h.lines.next(), 'No write.');
    h.stop.complete();
    await done;
    expect(h.afterRuns, isEmpty);
  });

  test('a failure of a run ends run() without waiting for stop', () async {
    final h = _Harness()..failWith = StateError('boom');

    await expectLater(h.start(), throwsA(isA<StateError>()));
  });

  test('stop waits for the run in flight', () async {
    final h = _Harness();
    final done = h.start();
    var finished = false;
    unawaited(done.then((_) => finished = true));
    await h.lines.next();
    await h.lines.next();
    h.blocking = true;
    await h.changed('/pkg/lib/a.dart');

    h.stop.complete();
    await Future<void>.delayed(_gap);
    expect(finished, isFalse);

    await h.release();
    await done;
    expect(await h.lines.next(), startsWith('Generated'));
    expect(h.calls.length, 2);
  });

  test('stop drops a change that is still debouncing', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();

    h.watcher.modify('/pkg/lib/a.dart');
    h.stop.complete();
    await done;

    expect(await h.lines.after(_gap), isEmpty);
    expect(h.calls.length, 1);
  });

  test('a failure of a run after stop is still thrown', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    h.blocking = true;
    await h.changed('/pkg/lib/a.dart');

    h.stop.complete();
    h.failWith = StateError('late');
    await h.release();

    await expectLater(done, throwsA(isA<StateError>()));
  });

  test('a failure of an event-triggered run ends run()', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    h.failWith = StateError('boom');

    h.watcher.modify('/pkg/lib/a.dart');

    await expectLater(done, throwsA(isA<StateError>()));
  });
}
