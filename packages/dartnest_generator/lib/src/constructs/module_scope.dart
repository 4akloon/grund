import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';
import 'scoped_provider.dart';

/// What each module of a package can inject, by the rules of the core
/// injector: own providers, then exports of imports (with re-exports), then
/// exports of global modules.
///
/// Built only for a graph of `@Module` classes of this package with no
/// import cycles; a module from another package is not in the scope, so it
/// contributes nothing (the caller skips packages that have one).
final class ModuleScope {
  /// Creates the scope of the package's modules.
  ModuleScope(this._modules)
    : _byType = {for (final module in _modules) module.type: module};

  final List<ModuleModel> _modules;

  final Map<TypeModel, ModuleModel> _byType;

  final Map<ModuleModel, Map<ProviderKey, ScopedProvider>> _visible = {};

  /// The providers [module] can inject, by key; computed once per module.
  ///
  /// Own providers win over exports of imports, which win over exports of
  /// global modules; among equals the first entry wins, as in the core.
  /// Ambiguity itself is not diagnosed here: the core throws
  /// `AmbiguousProviderError` at startup.
  Map<ProviderKey, ScopedProvider> visibleIn(ModuleModel module) =>
      _visible.putIfAbsent(module, () => _computeVisible(module));

  /// The ids of the modules that declare [key], in module order.
  List<String> declaring(ProviderKey key) => [
    for (final module in _modules)
      if (module.providers.any((provider) => provider.key == key)) module.id,
  ];

  Map<ProviderKey, ScopedProvider> _computeVisible(ModuleModel module) => {
    for (final global in _modules.reversed)
      if (global.isGlobal) ..._exported(global),
    for (final reference in module.imports.reversed) ..._exportedBy(reference),
    for (final provider in module.providers.reversed)
      provider.key: (owner: module, provider: provider),
  };

  Map<ProviderKey, ScopedProvider> _exportedBy(ModuleReference reference) =>
      switch (reference) {
        LocalModuleReference(:final type) => switch (_byType[type]) {
          final module? => _exported(module),
          null => const {},
        },
        OpaqueModuleReference() => const {},
      };

  Map<ProviderKey, ScopedProvider> _exported(ModuleModel module) => {
    for (final export in module.exports.reversed)
      ..._exportedEntry(module, export),
  };

  Map<ProviderKey, ScopedProvider> _exportedEntry(
    ModuleModel module,
    ModuleExport export,
  ) => switch (export) {
    KeyExport(:final key) => _ownProvider(module, key),
    ModuleReexport(module: final reference) => _exportedBy(reference),
  };

  Map<ProviderKey, ScopedProvider> _ownProvider(
    ModuleModel module,
    ProviderKey key,
  ) => {
    for (final provider in module.providers.reversed)
      if (provider.key == key) key: (owner: module, provider: provider),
  };
}
