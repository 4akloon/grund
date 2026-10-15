import 'errors.dart';
import 'module.dart';

/// The deduplicated, validated, topologically ordered set of modules
/// reachable from a root module.
///
/// Building the graph performs every structural check that does not need
/// provider instances: duplicate ids with different shape, import cycles,
/// duplicate provider keys, invalid exports, keys exported to one module by
/// several modules. Modules with equal ids are
/// compared by shape only (id, `global`, import ids, provider keys and
/// export keys); the first-seen instance wins.
final class ModuleGraph {
  ModuleGraph._(this.root, this.ordered, this._byId);

  /// The module [build] was called with.
  final Module root;

  /// Every distinct module once: imports before importers; global modules and
  /// their imports first; [root] last.
  final List<Module> ordered;

  final Map<String, Module> _byId;

  /// Builds and validates the graph reachable from [root].
  static ModuleGraph build(Module root) {
    final byId = <String, Module>{};
    final ordered = <Module>[];
    final path = <String>[]; // current DFS path, for cycle reporting

    void visit(Module module) {
      final seen = byId[module.id];
      if (seen != null) {
        // Already finished: only check that it is the same module.
        if (!identical(seen, module) && !_sameShape(seen, module)) {
          throw DuplicateModuleIdError(module.id);
        }
        return;
      }
      if (path.contains(module.id)) {
        final start = path.indexOf(module.id);
        throw CircularModuleImportError([...path.sublist(start), module.id]);
      }
      _validateProviders(module);
      _validateExports(module);
      path.add(module.id);
      for (final import in module.imports) {
        visit(import);
      }
      path.removeLast();
      byId[module.id] = module;
      ordered.add(module);
    }

    visit(root);
    final started = _globalsFirst(ordered);
    final globals = started.where((m) => m.global).toList();
    for (final module in started) {
      _validateVisibility(module, globals);
    }
    return ModuleGraph._(root, List.unmodifiable(started), byId);
  }

  /// The module with [id]; throws [UnknownModuleError] if absent.
  Module byId(String id) => _byId[id] ?? (throw UnknownModuleError(id));

  /// Whether a module with [id] is in the graph.
  bool contains(String id) => _byId.containsKey(id);

  /// Ids of every module that declares [key], in [ordered] order.
  List<String> modulesDeclaring(Object key) => [
    for (final m in ordered)
      if (m.declares(key)) m.id,
  ];

  /// Stable partition: global modules and the closure of their imports keep
  /// their imports-first order and start first, so every module can use a
  /// global module's async exports.
  static List<Module> _globalsFirst(List<Module> ordered) {
    final early = <String>{};
    final pending = [
      for (final module in ordered)
        if (module.global) module,
    ];
    while (pending.isNotEmpty) {
      final module = pending.removeLast();
      if (early.add(module.id)) pending.addAll(module.imports);
    }
    return [
      ...ordered.where((m) => early.contains(m.id)),
      ...ordered.where((m) => !early.contains(m.id)),
    ];
  }

  /// Rejects a key that reaches [module] from two owners within the imports
  /// tier or within the globals tier. Own providers and imports shadow lower
  /// tiers by design, so those are not ambiguity.
  static void _validateVisibility(Module module, List<Module> globals) {
    final viaImports = <Object, Set<String>>{};
    final importsSeen = <String>{};
    for (final import in module.imports) {
      _exportedOwners(import, viaImports, importsSeen);
    }
    _rejectAmbiguous(module, viaImports);
    final viaGlobals = <Object, Set<String>>{};
    final globalsSeen = <String>{};
    for (final global in globals) {
      if (global.id != module.id) {
        _exportedOwners(global, viaGlobals, globalsSeen);
      }
    }
    _rejectAmbiguous(module, viaGlobals);
  }

  /// Adds to [into] each key [module] exports, mapped to the module that
  /// declares it, following re-exported modules. [visited] holds module ids
  /// already walked, so one owner reached by several paths counts once.
  static void _exportedOwners(
    Module module,
    Map<Object, Set<String>> into,
    Set<String> visited,
  ) {
    if (!visited.add(module.id)) return;
    for (final export in module.exports) {
      if (export is Module) {
        _exportedOwners(export, into, visited);
      } else {
        into.putIfAbsent(export, () => {}).add(module.id);
      }
    }
  }

  static void _rejectAmbiguous(Module module, Map<Object, Set<String>> owners) {
    for (final MapEntry(:key, value: ids) in owners.entries) {
      if (ids.length < 2 || module.declares(key)) continue;
      throw AmbiguousProviderError(
        key: key,
        moduleId: module.id,
        owners: ids.toList()..sort(),
      );
    }
  }

  static void _validateProviders(Module module) {
    final keys = <Object>{};
    for (final provider in module.providers) {
      if (!keys.add(provider.key)) {
        throw DuplicateProviderError(key: provider.key, moduleId: module.id);
      }
    }
  }

  static void _validateExports(Module module) {
    for (final export in module.exports) {
      final valid = export is Module
          ? module.imports.any((m) => m.id == export.id)
          : module.declares(export);
      if (!valid) {
        throw InvalidExportError(export: export, moduleId: module.id);
      }
    }
  }

  /// Structural equality (id, `global`, import ids, provider keys and export
  /// keys; not factory configuration) used to accept the same dynamic module
  /// imported from several places.
  static bool _sameShape(Module a, Module b) {
    if (a.id != b.id || a.global != b.global) return false;
    if (!_sameList(a.imports.map((m) => m.id), b.imports.map((m) => m.id))) {
      return false;
    }
    if (!_sameList(
      a.providers.map((p) => p.key),
      b.providers.map((p) => p.key),
    )) {
      return false;
    }
    Object exportKey(Object e) => e is Module ? 'module:${e.id}' : e;
    return _sameList(a.exports.map(exportKey), b.exports.map(exportKey));
  }

  static bool _sameList(Iterable<Object> a, Iterable<Object> b) {
    final la = a.toList();
    final lb = b.toList();
    if (la.length != lb.length) return false;
    for (var i = 0; i < la.length; i++) {
      if (la[i] != lb[i]) return false;
    }
    return true;
  }
}
