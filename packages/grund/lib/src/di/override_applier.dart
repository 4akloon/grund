import '../errors/graph_errors.dart';
import 'binding.dart';
import 'module_node.dart';

/// Replaces bindings by key, for tests and development.
abstract final class OverrideApplier {
  /// [nodes] with every binding whose key an override names replaced by it.
  ///
  /// Throws [UnusedOverrideError] for an override that matches no binding.
  static List<ModuleNode> apply(
    List<ModuleNode> nodes,
    List<Binding<Object>> overrides,
  ) {
    var result = nodes;
    for (final override in overrides) {
      if (!result.any((n) => n.bindings.containsKey(override.key))) {
        throw UnusedOverrideError(override.key);
      }
      result = [
        for (final node in result)
          node.bindings.containsKey(override.key)
              ? node.replacing(override)
              : node,
      ];
    }
    return result;
  }
}
