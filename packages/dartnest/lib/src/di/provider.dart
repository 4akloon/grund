import 'dart:async';

import 'injector.dart';
import 'token.dart';

/// Builds a provider instance. Receives the injector of the module that
/// declares the provider, so it can resolve its own dependencies.
typedef ProviderFactory<T extends Object> = FutureOr<T> Function(
  Injector injector,
);

/// Declares how a module creates one singleton of type [T].
///
/// ```dart
/// Provider((i) => UsersRepo(i.get()));        // T inferred, key = UsersRepo
/// Provider<Clock>((i) => SystemClock());      // key = Clock
/// Provider.value(config);                     // constant
/// Provider.async((i) async => Db.connect());  // awaited at startup
/// Provider.value(url, token: dbUrl);          // keyed by a Token
/// ```
final class Provider<T extends Object> {
  /// Synchronous (or implicitly async) factory provider.
  Provider(ProviderFactory<T> create, {Token<T>? token})
      : this._(create, token: token, isAsync: false);

  /// Provides an already-built [value].
  Provider.value(T value, {Token<T>? token})
      : this._((_) => value, token: token, isAsync: false);

  /// Factory that must be awaited. The container awaits it during startup;
  /// a synchronous `get` of this key before that fails with
  /// `AsyncProviderNotReadyError`.
  Provider.async(Future<T> Function(Injector injector) create, {Token<T>? token})
      : this._(create, token: token, isAsync: true);

  Provider._(this._create, {Token<T>? token, required this.isAsync})
      : key = token ?? T {
    if (T == Object) {
      throw ArgumentError(
        'Provider type could not be inferred. '
        'Write Provider<MyType>(...) or return a concrete type from the factory.',
      );
    }
  }

  /// Lookup key: the [Type] `T`, or the [Token] when one was given.
  final Object key;

  /// Whether this provider was declared with [Provider.async].
  final bool isAsync;

  final ProviderFactory<T> _create;

  /// The provided type.
  Type get type => T;

  /// Invokes the factory. Callers must handle a returned [Future].
  FutureOr<T> create(Injector injector) => _create(injector);

  @override
  String toString() => key is Token ? 'Provider<$T>($key)' : 'Provider<$T>';
}
