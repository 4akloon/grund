import 'errors.dart';
import 'injector.dart';
import 'module.dart';
import 'module_graph.dart';
import 'module_injector.dart';
import 'resolution_trace.dart';

/// The started dependency graph: one [ModuleInjector] per module, every
/// provider instantiated.
///
/// ```dart
/// final container = await Container.create(appModule);
/// final users = container.root.get<UsersService>();
/// ```
final class Container {
  Container._(this.graph, this._injectors);

  /// The validated module graph.
  final ModuleGraph graph;

  final Map<String, ModuleInjector> _injectors;

  /// Builds, validates and starts the graph rooted at [root].
  ///
  /// Order of work:
  /// 1. [ModuleGraph.build] — structural validation, nothing is created.
  /// 2. One injector per module, wired to its imports and to global modules.
  /// 3. Modules in start order (see below); inside a module, providers in
  ///    declaration order. Async factories are awaited; sync factories may
  ///    pull sync dependencies on demand in any order.
  ///
  /// Modules start in imports-first order with global modules (and their
  /// imports) first, so any module may use a global module's async exports.
  /// The one remaining edge: a module inside a global's import closure that
  /// uses another global's async export may start before it; a sync `get`
  /// then throws `AsyncProviderNotReadyError`. Import that global explicitly.
  ///
  /// Throws an `InjectionError` subtype on the first problem; no partially
  /// started container is ever returned.
  static Future<Container> create(Module root) async {
    final graph = ModuleGraph.build(root);
    final trace = ResolutionTrace();
    final injectors = <String, ModuleInjector>{
      for (final module in graph.ordered)
        module.id: ModuleInjector(module, trace, graph.modulesDeclaring),
    };
    ModuleInjector of(String id) =>
        injectors[id] ?? (throw UnknownModuleError(id));
    for (final module in graph.ordered) {
      of(module.id).wire(
        imports: [for (final import in module.imports) of(import.id)],
        globals: [
          for (final other in graph.ordered)
            if (other.global && other.id != module.id) of(other.id),
        ],
      );
    }
    for (final module in graph.ordered) {
      await of(module.id).instantiateAll();
    }
    return Container._(graph, injectors);
  }

  /// Injector of the root module.
  Injector get root => injectorFor(graph.root.id);

  /// Injector of the module with [moduleId]; throws `UnknownModuleError`.
  Injector injectorFor(String moduleId) =>
      _injectors[moduleId] ?? (throw UnknownModuleError(moduleId));

  Future<void>? _closing;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Shuts the container down. Idempotent: every call returns the same
  /// future. Providers have no shutdown hooks yet, so nothing else happens;
  /// instances stay readable.
  Future<void> close() => _closing ??= Future<void>.value();
}
