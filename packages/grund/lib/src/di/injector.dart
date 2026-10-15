import 'token.dart';

/// Resolves provider instances inside one module's scope.
///
/// Lookups are synchronous and see: the module's own providers, providers
/// exported by its direct imports (including re-exported modules), and
/// providers exported by global modules. The container is immutable after
/// startup, so `get` is cheap and never creates request-scoped state.
abstract interface class Injector {
  /// Id of the module this injector belongs to.
  String get moduleId;

  /// Returns the singleton for [T], or for [token] when given.
  ///
  /// Throws `MissingProviderError` when nothing in scope provides the key and
  /// `AsyncProviderNotReadyError` when the provider is async and has not been
  /// created yet. Throws [ArgumentError] when [T] could not be inferred.
  T get<T extends Object>([Token<T>? token]);

  /// Like [get] but returns `null` instead of throwing `MissingProviderError`.
  T? maybeGet<T extends Object>([Token<T>? token]);
}
