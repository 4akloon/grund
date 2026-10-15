import 'dart:async';

import '../di/binding.dart';
import '../di/container.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../errors/app_errors.dart';
import '../errors/resolution_errors.dart';
import 'hot_reload_extension.dart';
import 'reassemble_report.dart';
import 'runner.dart';
import 'runner_set.dart';
import 'stop_signals.dart';

enum _AppState { created, started, closed }

/// The application: a root module, the container built from it and the
/// runners it finds there.
///
/// ```dart
/// Future<void> main(List<String> args) =>
///     App(root: AppModule()).run(only: Runners.fromArgs(args));
/// ```
final class App {
  /// Creates the application over [root]. Nothing is built until [start] or
  /// [run].
  ///
  /// [overrides] replace the bindings with the same key, wherever they are
  /// declared (tests, development).
  App({required this.root, this.overrides = const []});

  /// The root module.
  final Module root;

  /// Bindings that replace the ones with the same key.
  final List<Binding<Object>> overrides;

  _AppState _state = _AppState.created;
  _Running? _running;
  Future<ReassembleReport>? _reassembling;
  Future<void>? _closing;

  /// Whether [start] succeeded and [close] was not called yet.
  bool get isRunning => _state == _AppState.started;

  /// Whether the application was closed, or failed to start.
  bool get isClosed => _state == _AppState.closed;

  /// The container of the started application.
  Container get container => _started('use the container').container;

  /// Builds the graph, creates the singletons, prepares every runner and
  /// starts those that [only] selects (`null` selects all, `const {}` none).
  ///
  /// Every structural problem surfaces here, before any runner serves. When
  /// it fails, what was created is undone and the application is closed.
  Future<void> start({Set<String>? only}) async {
    _expect(_AppState.created, 'start');
    final Container container;
    try {
      container = await Container.create(
        ModuleGraph.build(root, overrides: overrides),
      );
    } on Object {
      // The graph or a factory is user code; nothing was left running.
      _state = _AppState.closed;
      rethrow;
    }
    try {
      final runners = RunnerSet.select(container.all<Runner>(), only: only);
      await runners.prepare(container.root);
      await runners.start(container.root);
      await _attach(runners);
      _running = _Running(container, runners, only);
      _state = _AppState.started;
    } on Object catch (error, stackTrace) {
      // Boundary: runners are user code; undo the container and report the
      // original failure.
      _state = _AppState.closed;
      await _undo(container, error, stackTrace);
      rethrow;
    }
  }

  // Registering the service extensions can fail; the runners are already
  // serving then, so they are stopped before the start is reported failed.
  Future<void> _attach(RunnerSet runners) async {
    try {
      HotReloadExtension.attach(this);
    } on Object {
      // Boundary: the VM service registration; undo, then report it.
      await runners.stop();
      rethrow;
    }
  }

  /// Starts, then waits for `SIGINT`/`SIGTERM` (or [signals]) and closes.
  Future<void> run({Set<String>? only, StopSignals? signals}) async {
    await start(only: only);
    await (signals ?? StopSignals()).wait();
    await close();
  }

  /// Rebuilds the graph from [root] and applies it to the running
  /// application (hot reload).
  ///
  /// Singletons whose module and key are unchanged are kept. When building
  /// the graph, creating singletons, or preparing, starting or reassembling
  /// a runner fails, the new container is abandoned, the error is thrown and
  /// the previous state keeps serving; the exception is a shared runner whose
  /// own `reassemble` fails, which is left stopped. When only stopping a
  /// dropped runner fails, the new state is kept and the [ShutdownError] is
  /// thrown afterwards.
  ///
  /// The `Disposable`s of the old container that
  /// were not adopted are not disposed by a reassemble, and runners are
  /// matched across a reassemble by instance, not by name.
  Future<ReassembleReport> reassemble() async {
    _started('reassemble');
    if (_reassembling != null) {
      throw const ApplicationStateError(
        operation: 'reassemble',
        reason: 'another reassemble is running',
      );
    }
    final pending = _reassemble();
    _reassembling = pending;
    try {
      return await pending;
    } finally {
      _reassembling = null;
    }
  }

  /// Stops the runners in reverse order, then runs the shutdown of the
  /// modules and singletons. Idempotent.
  ///
  /// Every step is tried; a [ShutdownError] lists those that failed.
  Future<void> close() => _closing ??= _close();

  Future<ReassembleReport> _reassemble() async {
    final current = _started('reassemble');
    final graph = ModuleGraph.build(root, overrides: overrides);
    final next = await current.container.reassemble(graph);
    final RunnerSet runners;
    final ({ReassembleReport report, List<ShutdownFailure> dropFailures})
    outcome;
    try {
      runners = RunnerSet.select(next.all<Runner>(), only: current.only);
      outcome = await current.runners.reassembleInto(runners, next.root);
    } on Object {
      // Boundary: runners are user code; the previous state keeps serving.
      await next.abandon();
      rethrow;
    }
    // Every runner now uses [next], so it is kept even if a dropped runner
    // failed to stop.
    _running = _Running(next, runners, current.only);
    if (outcome.dropFailures.isNotEmpty) {
      throw ShutdownError(outcome.dropFailures);
    }
    return outcome.report;
  }

  Future<void> _close() async {
    HotReloadExtension.detach(this);
    _state = _AppState.closed;
    final pending = _reassembling;
    if (pending != null) {
      try {
        await pending;
      } on Object {
        // The caller of reassemble gets this failure; here only the end of
        // the reassemble matters.
      }
    }
    final running = _running;
    final failures = [...?await running?.runners.stop()];
    try {
      await running?.container.close();
    } on ShutdownError catch (error) {
      failures.addAll(error.failures);
    }
    if (failures.isNotEmpty) throw ShutdownError(failures);
  }

  Future<void> _undo(
    Container container,
    Object cause,
    StackTrace causeStackTrace,
  ) async {
    try {
      await container.close();
    } on ShutdownError catch (error) {
      throw StartupRollbackError(
        cause: cause,
        causeStackTrace: causeStackTrace,
        failures: error.failures,
      );
    }
  }

  _Running _started(String operation) {
    _expect(_AppState.started, operation);
    return switch (_running) {
      final running? => running,
      null => throw StateError('a started application has a container'),
    };
  }

  void _expect(_AppState expected, String operation) {
    if (_state == expected) return;
    throw ApplicationStateError(
      operation: operation,
      reason: switch (_state) {
        _AppState.created => 'the application is not started',
        _AppState.started => 'the application is already started',
        _AppState.closed => 'the application is closed',
      },
    );
  }
}

final class _Running {
  _Running(this.container, this.runners, this.only);

  final Container container;
  final RunnerSet runners;
  final Set<String>? only;
}
