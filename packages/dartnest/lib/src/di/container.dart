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
  /// 3. Modules in imports-first order; inside a module, providers in
  ///    declaration order. Async factories are awaited; sync factories may
  ///    pull sync dependencies on demand in any order.
  ///
  /// Modules start in imports-first graph order, so a module that does not
  /// import a global module may start before it; a sync `get` of that
  /// global's async export then throws `AsyncProviderNotReadyError`. Import
  /// the global explicitly when you depend on its async providers.
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
}
