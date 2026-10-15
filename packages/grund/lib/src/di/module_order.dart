import 'module_identity.dart';
import 'module_node.dart';

/// Puts the global modules, and what they import, ahead of the rest.
abstract final class ModuleOrder {
  /// [nodes] (imports before importers) with the globals first, keeping the
  /// relative order within both halves.
  static List<ModuleNode> globalsFirst(List<ModuleNode> nodes) {
    final byIdentity = {for (final n in nodes) n.identity: n};
    final early = <ModuleIdentity>{};
    void include(ModuleIdentity identity) {
      if (!early.add(identity)) return;
      final node = byIdentity[identity];
      if (node != null) node.imports.forEach(include);
    }

    for (final node in nodes.where((n) => n.global)) {
      include(node.identity);
    }
    return [
      ...nodes.where((n) => early.contains(n.identity)),
      ...nodes.where((n) => !early.contains(n.identity)),
    ];
  }
}
