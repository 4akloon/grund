import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/type_model.dart';
import 'scoped_binding.dart';

/// Which bindings a module of the package can see, the way the core's
/// module graph decides it: its own bindings, then what its imports export,
/// then what global modules export; a nearer tier shadows a farther one.
///
/// Modules from other packages are not known here and see/export nothing.
final class ModuleScope {
  /// Creates the scope over the [_modules] of one package.
  ModuleScope(this._modules)
    : _byType = {for (final module in _modules) module.type: module};

  final List<ModuleModel> _modules;

  final Map<TypeModel, ModuleModel> _byType;

  final Map<ModuleModel, Map<BindingKey, ScopedBinding>> _visible = {};

  /// The bindings visible in [module], by key.
  ///
  /// The import graph must be acyclic: re-exports are followed.
  Map<BindingKey, ScopedBinding> visibleIn(ModuleModel module) =>
      _visible.putIfAbsent(module, () => _computeVisible(module));

  /// The display names of the modules that bind [key].
  List<String> declaring(BindingKey key) => [
    for (final module in _modules)
      if (module.bindings.any((binding) => binding.key == key))
        module.type.display,
  ];

  Map<BindingKey, ScopedBinding> _computeVisible(ModuleModel module) => {
    for (final global in _modules.reversed)
      if (global.isGlobal && global != module) ..._exported(global),
    for (final reference in module.imports.reversed) ..._exportedBy(reference),
    for (final binding in module.bindings.reversed)
      binding.key: (owner: module, binding: binding),
  };

  Map<BindingKey, ScopedBinding> _exportedBy(ModuleReference reference) =>
      switch (reference) {
        LocalModuleReference(:final type) => _exportedByType(type),
        OpaqueModuleReference() => const {},
      };

  Map<BindingKey, ScopedBinding> _exportedByType(TypeModel type) =>
      switch (_byType[type]) {
        final module? => _exported(module),
        null => const {},
      };

  Map<BindingKey, ScopedBinding> _exported(ModuleModel module) => {
    for (final export in module.exports.reversed)
      ...switch (export) {
        KeyExport(:final key) => _own(module, key),
        ModuleReexport(:final type) => _exportedByType(type),
      },
  };

  Map<BindingKey, ScopedBinding> _own(ModuleModel module, BindingKey key) => {
    for (final binding in module.bindings.reversed)
      if (binding.key == key) key: (owner: module, binding: binding),
  };
}
