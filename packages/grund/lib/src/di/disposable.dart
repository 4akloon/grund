import 'dart:async';

/// A value that releases resources when its owner goes away.
///
/// Singletons are disposed when the container closes, `Scoped` instances when
/// their call scope closes, in reverse creation order.
abstract interface class Disposable {
  /// Releases the resources of this value.
  FutureOr<void> dispose();
}
