import '../errors/graph_errors.dart';
import 'key.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'visible_binding.dart';

/// What every module of the graph can resolve.
///
/// A module sees its own bindings, then the exports of the modules it
/// imports (following re-exports), then the exports of global modules. An
/// earlier tier shadows a later one; two owners in one tier are ambiguous.
final class VisibilityIndex {
  VisibilityIndex._(this._visible);

  /// Builds the index for [nodes].
  ///
  /// Throws [AmbiguousProviderError].
  factory VisibilityIndex.build(List<ModuleNode> nodes) {
    final builder = _VisibilityBuilder(nodes);
    return VisibilityIndex._({
      for (final node in nodes) node.identity: builder.visibleTo(node),
    });
  }

  final Map<ModuleIdentity, Map<Key<Object>, VisibleBinding>> _visible;

  /// What [module] can resolve for [key], or `null`.
  VisibleBinding? lookup(ModuleIdentity module, Key<Object> key) =>
      _visible[module]?[key];
}

final class _VisibilityBuilder {
  _VisibilityBuilder(this._nodes)
    : _byIdentity = {for (final n in _nodes) n.identity: n};

  final List<ModuleNode> _nodes;
  final Map<ModuleIdentity, ModuleNode> _byIdentity;
  final Map<ModuleIdentity, Map<Key<Object>, VisibleBinding>> _exports = {};

  Map<Key<Object>, VisibleBinding> visibleTo(ModuleNode node) {
    final own = {
      for (final entry in node.bindings.entries)
        entry.key: VisibleBinding(node.identity, entry.value),
    };
    final imported = _pick(node, [
      for (final identity in node.imports) _exportsOf(identity),
    ], own);
    final fromGlobals = _pick(
      node,
      [
        for (final other in _nodes)
          if (other.global && other.identity != node.identity)
            _exportsOf(other.identity),
      ],
      {...imported, ...own},
    );
    return {...fromGlobals, ...imported, ...own};
  }

  Map<Key<Object>, VisibleBinding> _exportsOf(ModuleIdentity identity) {
    final cached = _exports[identity];
    if (cached != null) return cached;
    final node = _byIdentity[identity];
    if (node == null) return const {};
    final exported = {
      for (final MapEntry(:key, :value) in node.bindings.entries)
        if (node.exports.keys.contains(key))
          key: VisibleBinding(identity, value),
      for (final reexported in node.exports.modules) ..._exportsOf(reexported),
    };
    return _exports[identity] = exported;
  }

  /// The candidates of one tier, minus what [shadowing] already defines.
  Map<Key<Object>, VisibleBinding> _pick(
    ModuleNode node,
    List<Map<Key<Object>, VisibleBinding>> tier,
    Map<Key<Object>, VisibleBinding> shadowing,
  ) {
    final candidates = <Key<Object>, List<VisibleBinding>>{};
    for (final exports in tier) {
      for (final MapEntry(:key, :value) in exports.entries) {
        if (shadowing.containsKey(key)) continue;
        final owners = candidates.putIfAbsent(key, () => []);
        if (!owners.any((o) => o.owner == value.owner)) owners.add(value);
      }
    }
    return {
      for (final MapEntry(:key, :value) in candidates.entries)
        key: value.length == 1 ? value.single : _ambiguous(node, key, value),
    };
  }

  Never _ambiguous(
    ModuleNode node,
    Key<Object> key,
    List<VisibleBinding> owners,
  ) => throw AmbiguousProviderError(
    key: key,
    module: '${node.identity}',
    owners: ([for (final o in owners) '${o.owner}']..sort()),
  );
}
