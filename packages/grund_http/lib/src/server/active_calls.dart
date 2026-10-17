import '../adapter/in_flight_requests.dart';

import 'package:grund/grund.dart';

/// The requests the server is serving right now: counted, so that stopping
/// can wait for them, and cancellable, so that stopping can tell the ones
/// that stay behind to give up.
final class ActiveCalls {
  final InFlightRequests _inFlight = InFlightRequests();
  final Set<CancelSignal> _signals = {};

  /// Starts a call: the signal fires if the server gives up on it.
  CancelSignal open() {
    final signal = CancelSignal();
    _signals.add(signal);
    return signal;
  }

  /// Ends the call that [signal] belongs to.
  void release(CancelSignal signal) => _signals.remove(signal);

  /// Counts [serve] as in flight until it completes.
  Future<T> track<T>(Future<T> Function() serve) => _inFlight.track(serve);

  /// Completes when no tracked request is in flight.
  Future<void> get idle => _inFlight.idle;

  /// Fires the signal of every call still open.
  void cancelAll() {
    for (final signal in _signals.toList()) {
      signal.cancel();
    }
    _signals.clear();
  }
}
