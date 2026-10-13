import 'dart:async';

import 'injector.dart';

/// Non-generic view of a provider.
///
/// `Module.providers` is typed with this interface instead of
/// `Provider<Object>` so that Dart does not push `Object` into the type
/// inference of `Provider(...)` written inside the list.
abstract interface class ProviderSpec {
  /// Lookup key: a [Type] or a `Token`.
  Object get key;

  /// Whether the provider was declared with `Provider.async`.
  bool get isAsync;

  /// The provided type.
  Type get type;

  /// Invokes the factory. Callers must handle a returned [Future].
  FutureOr<Object> create(Injector injector);
}
