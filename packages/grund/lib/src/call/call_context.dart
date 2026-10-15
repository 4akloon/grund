import '../di/call_scope.dart';
import 'cancel_signal.dart';

/// What the code serving one call (a request, a message, a job run) sees.
///
/// Transports extend it with their own parts (`HttpCtx` adds the request).
/// Hooks put values on it with [set]; handlers read them back by type.
base class CallContext {
  /// Creates the context over [scope], which it closes with [close].
  CallContext(this.scope, {CancelSignal? cancel})
    : cancel = cancel ?? CancelSignal();

  /// The call scope that resolves bindings for this call.
  final CallScope scope;

  /// Fires when the call is no longer wanted.
  final CancelSignal cancel;

  /// The value of type [T] (and [name]) for this call: what a hook [set], a
  /// `Scoped` or `Transient` binding, or a singleton.
  T call<T extends Object>([String? name]) => scope<T>(name);

  /// Like [call], but `null` when there is none.
  T? maybe<T extends Object>([String? name]) => scope.maybe<T>(name);

  /// Makes [value] resolvable as [T] for the rest of the call.
  ///
  /// Write the type argument: the value is found under [T], not under its
  /// runtime type.
  void set<T extends Object>(T value, {String? name}) =>
      scope.set<T>(value, name: name);

  /// Ends the call: disposes its `Scoped` instances.
  Future<void> close() => scope.close();
}
