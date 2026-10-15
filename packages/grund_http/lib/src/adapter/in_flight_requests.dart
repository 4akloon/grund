import 'dart:async';

/// Counts requests being handled so that a graceful close can wait for them.
final class InFlightRequests {
  /// Creates an idle counter.
  InFlightRequests();

  int _count = 0;
  Completer<void>? _idle;

  /// Number of requests being handled.
  int get count => _count;

  /// Runs [handle] while counting it as in flight.
  Future<T> track<T>(Future<T> Function() handle) async {
    _count++;
    try {
      return await handle();
    } finally {
      _count--;
      if (_count == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Completes when no request is in flight.
  Future<void> get idle {
    if (_count == 0) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }
}
