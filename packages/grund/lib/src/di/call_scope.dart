import 'injector.dart';

/// An [Injector] bound to one call: an HTTP request, a message, a job run.
///
/// `Scoped` bindings are created at most once per call scope and disposed by
/// [close].
abstract interface class CallScope implements Injector {
  /// Makes [value] resolvable as `T` (and [name]) for the rest of the call.
  ///
  /// Hooks use it to hand over what they computed, e.g. the current user.
  void set<T extends Object>(T value, {String? name});

  /// Disposes the call's `Scoped` instances in reverse creation order.
  ///
  /// Throws a `ShutdownError` after trying all of them when some failed.
  Future<void> close();
}
