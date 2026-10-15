import 'dart:async';

import 'disposable.dart';
import 'key.dart';
import 'shutdown_steps.dart';
import 'visible_binding.dart';

/// What one call has accumulated: values set by hooks and `Scoped`
/// instances.
final class CallState {
  /// Values made resolvable with `CallScope.set`.
  final Map<Key<Object>, Object> values = {};

  /// `Scoped` instances in creation order.
  final Map<BindingId, Object> scoped = {};

  Future<void>? _closing;

  /// Disposes the scoped instances in reverse creation order; idempotent.
  Future<void> close() => _closing ??= _dispose();

  Future<void> _dispose() async {
    final steps = ShutdownSteps();
    for (final MapEntry(:key, :value) in scoped.entries.toList().reversed) {
      if (value is Disposable) {
        await steps.run('dispose ${key.$2} of ${key.$1}', value.dispose);
      }
    }
    steps.throwIfFailed();
  }
}
