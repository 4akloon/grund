import '../errors/resolution_errors.dart';
import 'binding.dart';
import 'container_lifecycle.dart';
import 'creation_plan.dart';
import 'injection_runtime.dart';
import 'injector.dart';
import 'module_graph.dart';

/// The created values of a [ModuleGraph]: singletons exist, modules are
/// initialised.
final class Container {
  Container._(this._runtime) : _lifecycle = ContainerLifecycle(_runtime);

  /// Creates every singleton in dependency order, then runs `onInit` of the
  /// modules.
  ///
  /// With [previous] the singletons whose module and key are unchanged are
  /// taken over instead of created again (hot reload). When a factory or
  /// `onInit` fails, what this call created is disposed again and the error
  /// is rethrown; no partially started container is returned.
  static Future<Container> create(
    ModuleGraph graph, {
    Container? previous,
  }) async {
    final container = Container._(InjectionRuntime(graph));
    try {
      await container._start(previous);
    } on Object catch (error, stackTrace) {
      // Boundary: factories and onInit are user code; undo what was done.
      final undone = await container._lifecycle.shutdown(freshOnly: true);
      if (undone.failures.isEmpty) rethrow;
      throw StartupRollbackError(
        cause: error,
        causeStackTrace: stackTrace,
        failures: undone.failures,
      );
    }
    return container;
  }

  final InjectionRuntime _runtime;
  final ContainerLifecycle _lifecycle;
  Future<void>? _closing;

  /// The injector of the root module.
  Injector get root => _runtime.viewOf(_runtime.graph.root);

  /// Every singleton whose binding type is a subtype of [T], in creation
  /// order.
  List<T> all<T extends Object>() => _runtime.all<T>();

  /// Builds the container of [newGraph], keeping the singletons that stayed
  /// the same. This container is left untouched; if creating the new one
  /// fails, the error is thrown and this one keeps working.
  Future<Container> reassemble(ModuleGraph newGraph) =>
      Container.create(newGraph, previous: this);

  /// Undoes what this container created itself, keeping what it took over
  /// from the container it replaced. For a reassemble that failed after
  /// [create].
  Future<void> abandon() async {
    (await _lifecycle.shutdown(freshOnly: true)).throwIfFailed();
  }

  /// Runs `onShutdown` of the modules in reverse order, then disposes the
  /// singletons in reverse creation order. Idempotent.
  ///
  /// Throws a [ShutdownError] after trying every step when some failed.
  Future<void> close() => _closing ??= _shutdown();

  Future<void> _shutdown() async {
    (await _lifecycle.shutdown(freshOnly: false)).throwIfFailed();
  }

  Future<void> _start(Container? previous) async {
    final kept = previous?._runtime;
    for (final id in CreationPlan.of(_runtime.graph).order) {
      final instance = kept?.singletons[id];
      if (instance != null &&
          kept?.bindingOf(id)?.scope == BindingScope.singleton) {
        _runtime.adopt(id, instance);
      } else {
        await _runtime.createSingleton(id);
      }
    }
    await _lifecycle.initModules(previous?._lifecycle.initialised ?? const {});
  }
}
