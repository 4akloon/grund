import 'binding.dart';
import 'dependency_validator.dart';
import 'module.dart';
import 'module_collector.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'module_order.dart';
import 'override_applier.dart';
import 'visibility_index.dart';

/// A validated module graph: every module, what it sees, nothing created yet.
final class ModuleGraph {
  ModuleGraph._(this.nodes, this.visibility, this._byIdentity, this.root);

  /// Reads and validates the graph below [root], with [overrides] applied.
  ///
  /// Every problem of structure, visibility and declared dependencies is a
  /// `GraphError` thrown here, before any factory runs.
  factory ModuleGraph.build(
    Module root, {
    List<Binding<Object>> overrides = const [],
  }) {
    final nodes = OverrideApplier.apply(
      ModuleOrder.globalsFirst(ModuleCollector().collect(root)),
      overrides,
    );
    final visibility = VisibilityIndex.build(nodes);
    DependencyValidator(nodes, visibility).validate();
    final rootIdentity = ModuleIdentity.of(root);
    return ModuleGraph._(nodes, visibility, {
      for (final node in nodes) node.identity: node,
    }, nodes.firstWhere((n) => n.identity == rootIdentity));
  }

  /// The modules: globals and their imports first, then each import before
  /// its importers.
  final List<ModuleNode> nodes;

  /// What every module can resolve.
  final VisibilityIndex visibility;

  final Map<ModuleIdentity, ModuleNode> _byIdentity;

  /// The node of [identity], or `null` when the graph has no such module.
  ModuleNode? nodeOf(ModuleIdentity identity) => _byIdentity[identity];

  /// The module the graph was built from.
  final ModuleNode root;
}
