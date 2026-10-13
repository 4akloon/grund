import 'dart:async';

import 'injector.dart';
import 'token.dart';

/// Builds a provider instance. Receives the injector of the module that
/// declares the provider, so it can resolve its own dependencies.
typedef ProviderFactory<T extends Object> =
    FutureOr<T> Function(Injector injector);

/// Non-generic view of a provider: what `Module.providers` holds.
///
/// It is non-generic so that Dart does not push `Object` into the type
/// inference of `Provider(...)` written inside the list literal. It is sealed
/// because the key/instance-type invariant (the instance created for [key] is
/// a [type]) is guaranteed only by [Provider]; other implementations could
/// break it.
sealed class ProviderSpec {
  /// Lookup key: a [Type] or a [Token].
  Object get key;

  /// Whether the provider was declared with [Provider.async].
  bool get isAsync;

  /// The provided type.
  Type get type;

  /// Invokes the factory. Callers must handle a returned [Future].
  FutureOr<Object> create(Injector injector);
}

/// Declares how a module creates one singleton of type [T].
///
/// ```dart
/// Provider((i) => UsersRepo(i.get()));        // T inferred, key = UsersRepo
/// Provider<Clock>((i) => SystemClock());      // key = Clock
/// Provider.value(config);                     // constant
/// Provider.async((i) async => Db.connect());  // awaited at startup
/// Provider.value(url, token: dbUrl);          // keyed by a Token
/// ```
///
/// A sync `get` of a plain-async closure (an `async` factory declared without
/// `Provider.async`) invokes the factory once and discards the future;
/// startup invokes it again. This double invocation happens only on the
/// error path.
final class Provider<T extends Object> implements ProviderSpec {
  /// Synchronous (or implicitly async) factory provider.
  Provider(ProviderFactory<T> create, {Token<T>? token})
    : this._(create, token: token, isAsync: false);

  /// Provides an already-built [value].
  Provider.value(T value, {Token<T>? token})
    : this._((_) => value, token: token, isAsync: false);

  /// Factory that must be awaited. The container awaits it during startup;
  /// a synchronous `get` of this key before that fails with
  /// `AsyncProviderNotReadyError`.
  Provider.async(
    Future<T> Function(Injector injector) create, {
    Token<T>? token,
  }) : this._(create, token: token, isAsync: true);

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
  @override
  final Object key;

  /// Whether this provider was declared with [Provider.async].
  @override
  final bool isAsync;

  final ProviderFactory<T> _create;

  /// The provided type.
  @override
  Type get type => T;

  /// Invokes the factory. Callers must handle a returned [Future].
  @override
  FutureOr<T> create(Injector injector) => _create(injector);

  @override
  String toString() => key is Token ? 'Provider<$T>($key)' : 'Provider<$T>';
}
