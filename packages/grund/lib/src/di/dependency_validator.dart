import '../errors/graph_errors.dart';
import 'binding.dart';
import 'key.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'visibility_index.dart';
import 'visible_binding.dart';

/// Checks the declared dependencies of a graph before any factory runs.
///
/// Bindings without `dependsOn` are skipped: they are checked when their
/// factory resolves something.
final class DependencyValidator {
  /// Creates a validator for [nodes] and what they see.
  DependencyValidator(this._nodes, this._visibility)
    : _byIdentity = {for (final n in _nodes) n.identity: n};

  final List<ModuleNode> _nodes;
  final VisibilityIndex _visibility;
  final Map<ModuleIdentity, ModuleNode> _byIdentity;
  final Map<BindingId, _Mark> _marks = {};

  /// Throws [MissingProviderError], [ProviderNotVisibleError],
  /// [CircularDependencyError] or [CaptiveDependencyError].
  void validate() {
    for (final node in _nodes) {
      for (final binding in node.bindings.values) {
        _requireVisible(node, binding);
      }
    }
    for (final ref in _allBindings()) {
      _findCycle(ref, const []);
    }
    for (final ref in _allBindings()) {
      if (ref.binding.scope == BindingScope.singleton) _findCaptive(ref);
    }
  }

  Iterable<VisibleBinding> _allBindings() sync* {
    for (final node in _nodes) {
      for (final binding in node.bindings.values) {
        yield VisibleBinding(node.identity, binding);
      }
    }
  }

  List<VisibleBinding> _dependenciesOf(VisibleBinding ref) {
    final dependencies = <VisibleBinding>[];
    for (final key in ref.binding.dependsOn ?? const <Key<Object>>[]) {
      final visible = _visibility.lookup(ref.owner, key);
      if (visible != null) dependencies.add(visible);
    }
    return dependencies;
  }

  void _requireVisible(ModuleNode node, Binding<Object> binding) {
    for (final key in binding.dependsOn ?? const <Key<Object>>[]) {
      if (_visibility.lookup(node.identity, key) != null) continue;
      final declaring = [
        for (final other in _nodes)
          if (other.bindings.containsKey(key)) other.identity,
      ];
      if (declaring.isEmpty) {
        throw MissingProviderError(
          key: key,
          module: '${node.identity}',
          requiredBy: binding.key,
        );
      }
      throw ProviderNotVisibleError(
        key: key,
        module: '${node.identity}',
        requiredBy: binding.key,
        declaredIn: [for (final d in declaring) '$d'],
        importChain: _importChain(node.identity, declaring),
      );
    }
  }

  List<String> _importChain(ModuleIdentity from, List<ModuleIdentity> targets) {
    final parents = <ModuleIdentity, ModuleIdentity>{};
    final queue = [from];
    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      if (targets.contains(current) && current != from) {
        final chain = [current];
        while (chain.first != from) {
          final parent = parents[chain.first];
          if (parent == null) break;
          chain.insert(0, parent);
        }
        return [for (final step in chain) '$step'];
      }
      for (final next
          in _byIdentity[current]?.imports ?? const <ModuleIdentity>[]) {
        if (next != from &&
            parents.putIfAbsent(next, () => current) == current) {
          queue.add(next);
        }
      }
    }
    return const [];
  }

  void _findCycle(VisibleBinding ref, List<VisibleBinding> path) {
    switch (_marks[ref.id]) {
      case _Mark.done:
        return;
      case _Mark.active:
        final start = path.indexWhere((p) => p.id == ref.id);
        throw CircularDependencyError([
          for (final step in [...path.sublist(start), ref]) step.binding.key,
        ]);
      case null:
        _marks[ref.id] = _Mark.active;
        for (final dependency in _dependenciesOf(ref)) {
          _findCycle(dependency, [...path, ref]);
        }
        _marks[ref.id] = _Mark.done;
    }
  }

  void _findCaptive(VisibleBinding singleton) {
    final seen = <BindingId>{};
    void walk(VisibleBinding ref, List<Key<Object>> path) {
      for (final dependency in _dependenciesOf(ref)) {
        if (!seen.add(dependency.id)) continue;
        final trail = [...path, dependency.binding.key];
        switch (dependency.binding.scope) {
          case BindingScope.scoped:
            throw CaptiveDependencyError(
              singleton: singleton.binding.key,
              scoped: dependency.binding.key,
              path: trail,
            );
          case BindingScope.transient:
            walk(dependency, trail);
          case BindingScope.singleton:
            break;
        }
      }
    }

    walk(singleton, [singleton.binding.key]);
  }
}

enum _Mark { active, done }
