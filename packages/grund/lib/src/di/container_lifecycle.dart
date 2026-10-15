import '../errors/grund_error.dart';
import '../errors/resolution_errors.dart';
import 'disposable.dart';
import 'injection_runtime.dart';
import 'module_identity.dart';
import 'shutdown_steps.dart';

/// Runs the lifecycle of the modules and singletons of one container.
final class ContainerLifecycle {
  /// Creates the lifecycle over [_runtime].
  ContainerLifecycle(this._runtime);

  final InjectionRuntime _runtime;
  final Set<ModuleIdentity> _initialised = {};
  final Set<ModuleIdentity> _fresh = {};

  /// Calls `onInit` of every module that [carried] does not already hold,
  /// in module order. A carried module counts as initialised.
  Future<void> initModules(Set<ModuleIdentity> carried) async {
    for (final node in _runtime.graph.nodes) {
      final identity = node.identity;
      if (carried.contains(identity)) {
        _initialised.add(identity);
        continue;
      }
      try {
        await node.module.onInit(_runtime.viewOf(node));
      } on Object catch (error, stackTrace) {
        // Boundary: onInit is user code.
        if (error is GrundError) rethrow;
        Error.throwWithStackTrace(
          ModuleLifecycleError(
            module: '$identity',
            phase: 'onInit',
            error: error,
            stackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
      _initialised.add(identity);
      _fresh.add(identity);
    }
  }

  /// Calls `onShutdown` in reverse module order, then disposes singletons in
  /// reverse creation order. With [freshOnly] it leaves modules and
  /// singletons that came from a previous container alone.
  Future<ShutdownSteps> shutdown({required bool freshOnly}) async {
    final steps = ShutdownSteps();
    final modules = freshOnly ? _fresh : _initialised;
    for (final node in _runtime.graph.nodes.reversed) {
      if (!modules.contains(node.identity)) continue;
      await steps.run(
        'onShutdown of ${node.identity}',
        () => node.module.onShutdown(_runtime.viewOf(node)),
      );
    }
    for (final MapEntry(:key, :value)
        in _runtime.singletons.entries.toList().reversed) {
      if (value is! Disposable) continue;
      if (freshOnly && _runtime.adopted.contains(key)) continue;
      await steps.run('dispose ${key.$2} of ${key.$1}', value.dispose);
    }
    return steps;
  }

  /// The identities of the modules that count as initialised: the ones whose
  /// `onInit` this container ran and the ones carried over from the previous
  /// container.
  Set<ModuleIdentity> get initialised => Set.unmodifiable(_initialised);
}
