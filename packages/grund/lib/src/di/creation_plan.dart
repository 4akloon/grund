import 'binding.dart';
import 'key.dart';
import 'module_graph.dart';
import 'visible_binding.dart';

/// The order in which singletons are created: every singleton after the
/// ones its factory declares in `dependsOn`, otherwise in the order of the
/// modules and of the declarations.
final class CreationPlan {
  CreationPlan._(this.order);

  /// Plans the singletons of [graph].
  factory CreationPlan.of(ModuleGraph graph) {
    final builder = _PlanBuilder(graph);
    for (final node in graph.nodes) {
      for (final binding in node.bindings.values) {
        builder.visit(VisibleBinding(node.identity, binding));
      }
    }
    return CreationPlan._(builder.order);
  }

  /// The singletons to create, first to last.
  final List<BindingId> order;
}

final class _PlanBuilder {
  _PlanBuilder(this._graph);

  final ModuleGraph _graph;
  final Set<BindingId> _visited = {};
  final List<BindingId> order = [];

  void visit(VisibleBinding ref) {
    if (!_visited.add(ref.id)) return;
    for (final key in ref.binding.dependsOn ?? const <Key<Object>>[]) {
      final dependency = _graph.visibility.lookup(ref.owner, key);
      if (dependency != null) visit(dependency);
    }
    if (ref.binding.scope == BindingScope.singleton) order.add(ref.id);
  }
}
