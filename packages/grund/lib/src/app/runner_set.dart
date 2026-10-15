import 'dart:async';

import '../di/injector.dart';
import '../di/shutdown_steps.dart';
import '../errors/app_errors.dart';
import '../errors/grund_error.dart';
import '../errors/resolution_errors.dart';
import 'reassemble_report.dart';
import 'runner.dart';

/// The runners of one container: which exist, which `only` selected and
/// which are running.
final class RunnerSet {
  RunnerSet._(this._available, this._selected);

  /// Selects from [available] the runners named in [only] (`null` selects
  /// all).
  ///
  /// Throws [DuplicateRunnerError] when two runners share a name and
  /// [UnknownRunnerError] when [only] names a runner that does not exist.
  factory RunnerSet.select(List<Runner> available, {Set<String>? only}) {
    final names = <String>{};
    for (final runner in available) {
      if (!names.add(runner.name)) throw DuplicateRunnerError(runner.name);
    }
    if (only == null) return RunnerSet._(available, available);
    final unknown = [
      for (final name in only)
        if (!names.contains(name)) name,
    ]..sort();
    if (unknown.isNotEmpty) {
      throw UnknownRunnerError(
        unknown: unknown,
        available: names.toList()..sort(),
      );
    }
    return RunnerSet._(available, [
      for (final runner in available)
        if (only.contains(runner.name)) runner,
    ]);
  }

  final List<Runner> _available;
  final List<Runner> _selected;
  final List<Runner> _running = [];

  /// Prepares every runner, the unselected ones too.
  Future<void> prepare(Injector injector) async {
    for (final runner in _available) {
      await _guard(runner, 'prepare', () => runner.prepare(injector));
    }
  }

  /// Starts the selected runners in order.
  ///
  /// When one fails, the ones already started are stopped again and the
  /// failure is thrown.
  Future<void> start(Injector injector) async {
    try {
      for (final runner in _selected) {
        await _guard(runner, 'start', () => runner.start(injector));
        _running.add(runner);
      }
    } on Object catch (error, stackTrace) {
      // Boundary: runners are user code; undo what was started and let the
      // original failure through.
      final failures = await stop();
      if (failures.isEmpty) rethrow;
      throw StartupRollbackError(
        cause: error,
        causeStackTrace: stackTrace,
        failures: failures,
      );
    }
  }

  /// Stops the running runners in reverse order, trying all of them.
  ///
  /// Returns the failures instead of throwing, so the caller can add the
  /// shutdown of the container to them.
  Future<List<ShutdownFailure>> stop() => _stop(_running.reversed.toList());

  /// Applies a reassemble: this set (of the previous container) hands over to
  /// [next] (of the new one), which gets [injector].
  ///
  /// A runner that is in both is reassembled; a runner only [next] selects is
  /// prepared and started; a running runner [next] no longer has is stopped.
  /// When one of those steps fails, what [next] started is stopped again and
  /// this set keeps running. A shared runner whose own `reassemble` fails is
  /// the exception: its default implementation stops it first, so it stays
  /// stopped. Runners are matched by instance, not by name.
  ///
  /// When only stopping a dropped runner fails, everything else has already
  /// moved to [next]; the failures are returned in the outcome and [next]
  /// is the state to keep.
  Future<({ReassembleReport report, List<ShutdownFailure> dropFailures})>
  reassembleInto(RunnerSet next, Injector injector) async {
    var report = ReassembleReport.none;
    try {
      for (final runner in next._available) {
        report = report.merge(await next._adopt(runner, this, injector));
      }
    } on Object {
      // Boundary: runners are user code; the previous set keeps serving.
      await next._stop([
        for (final runner in next._running.reversed)
          if (!_running.contains(runner)) runner,
      ]);
      rethrow;
    }
    final dropped = [
      for (final runner in _running.reversed)
        if (!next._running.contains(runner)) runner,
    ];
    return (report: report, dropFailures: await _stop(dropped));
  }

  Future<ReassembleReport> _adopt(
    Runner runner,
    RunnerSet previous,
    Injector injector,
  ) async {
    if (previous._running.contains(runner)) {
      final report = await _guard(
        runner,
        'reassemble',
        () => runner.reassemble(injector),
      );
      _running.add(runner);
      return report;
    }
    await _guard(runner, 'prepare', () => runner.prepare(injector));
    if (_selected.contains(runner)) {
      await _guard(runner, 'start', () => runner.start(injector));
      _running.add(runner);
    }
    return ReassembleReport.none;
  }

  Future<List<ShutdownFailure>> _stop(List<Runner> runners) async {
    final steps = ShutdownSteps();
    for (final runner in runners) {
      await steps.run('stop runner ${runner.name}', runner.stop);
      _running.remove(runner);
    }
    return steps.failures;
  }

  // Boundary: runners are user code. A GrundError keeps its type, anything
  // else is wrapped with the runner and the phase.
  Future<T> _guard<T>(
    Runner runner,
    String phase,
    FutureOr<T> Function() action,
  ) async {
    try {
      return await action();
    } on GrundError {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RunnerError(
          runner: runner.name,
          phase: phase,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }
}
