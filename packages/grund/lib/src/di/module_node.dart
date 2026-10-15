import '../errors/graph_errors.dart';
import 'binding.dart';
import 'key.dart';
import 'module.dart';
import 'module_exports.dart';
import 'module_identity.dart';
import 'module_shape.dart';

/// A module of the graph with its declarations read once and checked.
final class ModuleNode {
  const ModuleNode._({
    required this.identity,
    required this.module,
    required this.imports,
    required this.bindings,
    required this.exports,
  });

  /// Reads and checks [module], whose [imports] were already read.
  ///
  /// Throws [DuplicateBindingError] and [InvalidExportError].
  factory ModuleNode.of(Module module, List<Module> imports) {
    final identity = ModuleIdentity.of(module);
    final importIdentities = [for (final m in imports) ModuleIdentity.of(m)];
    final bindings = <Key<Object>, Binding<Object>>{};
    for (final binding in module.bindings) {
      if (bindings.containsKey(binding.key)) {
        throw DuplicateBindingError(key: binding.key, module: '$identity');
      }
      bindings[binding.key] = binding;
    }
    final keys = <Key<Object>>[];
    final reexports = <ModuleIdentity>[];
    for (final export in module.exports) {
      switch (export) {
        case Key<Object>() when bindings.containsKey(export):
          keys.add(export);
        case Module() when importIdentities.contains(ModuleIdentity.of(export)):
          reexports.add(ModuleIdentity.of(export));
        default:
          throw InvalidExportError(export: export, module: '$identity');
      }
    }
    return ModuleNode._(
      identity: identity,
      module: module,
      imports: importIdentities,
      bindings: bindings,
      exports: ModuleExports(keys: keys, modules: reexports),
    );
  }

  /// Who this module is.
  final ModuleIdentity identity;

  /// The instance the declarations were read from.
  final Module module;

  /// Identities of the imported modules, in declaration order.
  final List<ModuleIdentity> imports;

  /// The bindings in declaration order.
  final Map<Key<Object>, Binding<Object>> bindings;

  /// What importers of this module may use.
  final ModuleExports exports;

  /// Whether the exports are visible everywhere.
  bool get global => module.global;

  /// What this module declares, for comparing two instances of one identity.
  ModuleShape get shape => ModuleShape(
    imports: imports.toSet(),
    bindings: {for (final b in bindings.values) (b.key, b.scope)},
    exports: {...exports.keys, ...exports.modules},
    global: global,
  );

  /// This node with [replacement] in place of the binding of its key.
  ModuleNode replacing(Binding<Object> replacement) => ModuleNode._(
    identity: identity,
    module: module,
    imports: imports,
    bindings: {...bindings, replacement.key: replacement},
    exports: exports,
  );
}
