import 'dart:async';

/// Tells the code of a call that its result is no longer wanted.
final class CancelSignal {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Signals cancellation; further calls do nothing.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
