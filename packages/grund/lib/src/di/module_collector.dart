import '../errors/graph_errors.dart';
import 'module.dart';
import 'module_identity.dart';
import 'module_node.dart';

/// Reads a module and everything it imports into nodes, imports first.
final class ModuleCollector {
  final Map<ModuleIdentity, ModuleNode> _nodes = {};
  final List<ModuleIdentity> _path = [];

  /// The nodes reachable from [root], each import before its importers and
  /// [root] last.
  ///
  /// Throws [CircularModuleImportError] and [ConflictingModuleError], and
  /// what [ModuleNode.of] throws.
  List<ModuleNode> collect(Module root) {
    _visit(root);
    return _nodes.values.toList();
  }

  void _visit(Module module) {
    final identity = ModuleIdentity.of(module);
    final known = _nodes[identity];
    if (known != null) {
      _requireSameShape(known, module);
      return;
    }
    final start = _path.indexOf(identity);
    if (start >= 0) {
      throw CircularModuleImportError([
        for (final step in [..._path.sublist(start), identity]) '$step',
      ]);
    }
    final imports = module.imports;
    _path.add(identity);
    imports.forEach(_visit);
    _path.removeLast();
    _nodes[identity] = ModuleNode.of(module, imports);
  }

  void _requireSameShape(ModuleNode known, Module other) {
    if (identical(known.module, other)) return;
    if (ModuleNode.of(other, other.imports).shape != known.shape) {
      throw ConflictingModuleError('${known.identity}');
    }
  }
}
