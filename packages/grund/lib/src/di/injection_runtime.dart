import '../errors/graph_errors.dart';
import '../errors/grund_error.dart';
import '../errors/resolution_errors.dart';
import 'binding.dart';
import 'call_state.dart';
import 'call_view.dart';
import 'injector.dart';
import 'key.dart';
import 'module_graph.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'module_view.dart';
import 'visible_binding.dart';

/// Creates and finds the values of one started graph.
final class InjectionRuntime {
  /// Creates the runtime of [graph]; nothing is created yet.
  InjectionRuntime(this.graph);

  /// The graph the values belong to.
  final ModuleGraph graph;

  /// Created singletons in creation order.
  final Map<BindingId, Object> singletons = {};

  /// Singletons taken over from a previous container.
  final Set<BindingId> adopted = {};

  final Map<ModuleIdentity, ModuleView> _views = {};
  final List<BindingId> _creating = [];

  /// The injector of [node].
  Injector viewOf(ModuleNode node) =>
      _views.putIfAbsent(node.identity, () => ModuleView(this, node));

  /// Takes over [instance] for [id] instead of creating it.
  void adopt(BindingId id, Object instance) {
    singletons[id] = instance;
    adopted.add(id);
  }

  /// The binding of [id], or `null`.
  Binding<Object>? bindingOf(BindingId id) =>
      graph.nodeOf(id.$1)?.bindings[id.$2];

  /// Every singleton created so far whose binding type is a subtype of [T].
  List<T> all<T extends Object>() => [
    for (final MapEntry(:key, :value) in singletons.entries)
      if (bindingOf(key) is Binding<T>) value as T,
  ];

  /// The value of [key] as seen from [from], or `null` when nothing visible
  /// matches. Values set on [state] win.
  Object? find(ModuleNode from, Key<Object> key, CallState? state) {
    final set = state?.values[key];
    if (set != null) return set;
    final visible = graph.visibility.lookup(from.identity, key);
    return visible == null ? null : _instance(visible, state);
  }

  /// Like [find], but throws [MissingProviderError] when there is none.
  T resolve<T extends Object>(ModuleNode from, Key<T> key, CallState? state) {
    final value = find(from, key, state);
    if (value != null) return value as T;
    throw MissingProviderError(
      key: key,
      module: '${from.identity}',
      requiredBy: _creating.isEmpty ? null : _creating.last.$2,
    );
  }

  /// Creates the singleton [id], waiting for an asynchronous factory.
  Future<void> createSingleton(BindingId id) async {
    final binding = bindingOf(id);
    final node = graph.nodeOf(id.$1);
    if (binding == null || node == null || singletons.containsKey(id)) return;
    final visible = VisibleBinding(id.$1, binding);
    _enter(visible);
    try {
      singletons[id] = await binding.create(viewOf(node));
    } on Object catch (error, stackTrace) {
      // Boundary: factories are user code.
      _wrap(visible, error, stackTrace);
    } finally {
      _creating.removeLast();
    }
  }

  Object _instance(VisibleBinding visible, CallState? state) {
    final id = visible.id;
    switch (visible.binding) {
      case Singleton():
        return singletons[id] ?? (singletons[id] = _create(visible, null));
      case Transient():
        return _create(visible, state);
      case Scoped():
        if (state == null) {
          throw ScopedOutsideCallError(
            key: visible.binding.key,
            module: '${visible.owner}',
          );
        }
        return state.scoped[id] ?? (state.scoped[id] = _create(visible, state));
    }
  }

  Object _create(VisibleBinding visible, CallState? state) {
    final node = graph.nodeOf(visible.owner);
    if (node == null) throw StateError('Unknown module ${visible.owner}');
    final injector = state == null ? viewOf(node) : CallView(this, node, state);
    _enter(visible);
    try {
      final created = visible.binding.create(injector);
      if (created is Future<Object>) {
        created.ignore();
        throw AsyncProviderNotReadyError(
          key: visible.binding.key,
          module: '${visible.owner}',
          chain: _chain(),
        );
      }
      return created;
    } on Object catch (error, stackTrace) {
      // Boundary: factories are user code.
      _wrap(visible, error, stackTrace);
    } finally {
      _creating.removeLast();
    }
  }

  void _enter(VisibleBinding visible) {
    final start = _creating.indexOf(visible.id);
    if (start >= 0) {
      throw CircularDependencyError([
        for (final id in [..._creating.sublist(start), visible.id]) id.$2,
      ]);
    }
    _creating.add(visible.id);
  }

  List<Key<Object>> _chain() => [
    for (final id in _creating.reversed.skip(1)) id.$2,
  ];

  Never _wrap(VisibleBinding visible, Object error, StackTrace stackTrace) {
    if (error is GrundError) throw error;
    Error.throwWithStackTrace(
      ProviderCreationError(
        key: visible.binding.key,
        module: '${visible.owner}',
        chain: _chain(),
        error: error,
        stackTrace: stackTrace,
      ),
      stackTrace,
    );
  }
}
