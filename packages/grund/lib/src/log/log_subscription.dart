import 'dart:async';

import 'package:logging/logging.dart';

/// The attachment of a `LogOutput` to `Logger.root`; [cancel] detaches it and
/// puts the root level back.
final class LogSubscription {
  /// Creates a subscription that has nothing to undo.
  LogSubscription.empty() : this._(null, null);

  /// Creates the subscription over [_subscription]; [cancel] also restores
  /// the root level [_previousLevel].
  LogSubscription.of(
    StreamSubscription<LogRecord> this._subscription,
    Level this._previousLevel,
  );

  LogSubscription._(this._subscription, this._previousLevel);

  final StreamSubscription<LogRecord>? _subscription;
  final Level? _previousLevel;

  // Set before the first await, so a second call, also a concurrent one,
  // does not restore the root level again over a level set since.
  bool _isCancelled = false;

  /// Stops the output. Idempotent.
  Future<void> cancel() async {
    final subscription = _subscription;
    if (subscription == null || _isCancelled) return;
    _isCancelled = true;
    await subscription.cancel();
    final previous = _previousLevel;
    if (previous != null) Logger.root.level = previous;
  }
}
