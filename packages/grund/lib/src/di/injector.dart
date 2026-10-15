import 'call_scope.dart';

/// Resolves bindings as one module sees them.
abstract interface class Injector {
  /// The value of type [T] (and [name], when given) visible to this injector.
  ///
  /// Throws a `MissingProviderError` when nothing visible matches.
  T call<T extends Object>([String? name]);

  /// Like [call], but `null` when nothing visible matches.
  T? maybe<T extends Object>([String? name]);

  /// Every singleton of the whole graph whose binding type is a subtype of
  /// [T], in creation order.
  ///
  /// Visibility is not applied: transports collect their contributions this
  /// way. Called while the graph is still starting, it sees only the
  /// singletons created so far.
  List<T> all<T extends Object>();

  /// Opens a call scope that resolves what this injector's module sees.
  CallScope openCall();
}
