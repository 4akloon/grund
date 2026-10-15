import 'call_scope.dart';
import 'call_state.dart';
import 'call_view.dart';
import 'injection_runtime.dart';
import 'injector.dart';
import 'key.dart';
import 'module_node.dart';

/// The [Injector] of one module: it resolves what that module sees.
final class ModuleView implements Injector {
  /// Creates the view of [node] over [_runtime].
  ModuleView(this._runtime, this.node);

  final InjectionRuntime _runtime;

  /// The module this view belongs to.
  final ModuleNode node;

  @override
  T call<T extends Object>([String? name]) =>
      _runtime.resolve(node, Key<T>(name), null);

  @override
  T? maybe<T extends Object>([String? name]) =>
      _runtime.find(node, Key<T>(name), null) as T?;

  @override
  List<T> all<T extends Object>() => _runtime.all<T>();

  @override
  CallScope openCall() => CallView(_runtime, node, CallState());
}
