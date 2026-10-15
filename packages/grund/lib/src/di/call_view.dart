import 'call_scope.dart';
import 'call_state.dart';
import 'injection_runtime.dart';
import 'key.dart';
import 'module_node.dart';

/// The [CallScope] of one call, resolving what [node] sees.
final class CallView implements CallScope {
  /// Creates the view of [node] over [_runtime] for the call of [_state].
  CallView(this._runtime, this.node, this._state);

  final InjectionRuntime _runtime;
  final CallState _state;

  /// The module whose visibility applies.
  final ModuleNode node;

  @override
  T call<T extends Object>([String? name]) =>
      _runtime.resolve(node, Key<T>(name), _state);

  @override
  T? maybe<T extends Object>([String? name]) =>
      _runtime.find(node, Key<T>(name), _state) as T?;

  @override
  List<T> all<T extends Object>() => _runtime.all<T>();

  @override
  CallScope openCall() => CallView(_runtime, node, CallState());

  @override
  void set<T extends Object>(T value, {String? name}) {
    _state.values[Key<T>(name)] = value;
  }

  @override
  Future<void> close() => _state.close();
}
