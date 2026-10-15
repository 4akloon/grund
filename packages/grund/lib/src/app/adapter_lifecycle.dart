import 'dart:async';

import 'in_flight_requests.dart';

/// The listen/close state machine every `HttpAdapter` needs, independent of
/// the server library: [S] is the server object the adapter binds.
///
/// An adapter creates one, calls [start] from `listen` and [close] from
/// `close`, and counts its requests with [inFlight]. The lifecycle
///
/// - allows one successful [start] and refuses it after [close] (a
///   [StateError]); a failed bind can be retried;
/// - closes a server that finished binding after [close] was called;
/// - makes [close] idempotent: every call returns the same future;
/// - lets `close(force: true)` end a graceful close that is still waiting;
/// - gives up waiting for the requests in flight after [closeTimeout] and
///   drops the remaining connections as `force` does.
final class AdapterLifecycle<S extends Object> {
  /// Creates the lifecycle of the adapter called [name] (used in error
  /// messages); [closeTimeout] bounds the wait of a graceful [close]
  /// (`null`: no limit).
  AdapterLifecycle({required this.name, required this.closeTimeout});

  /// The adapter's class name, for error messages.
  final String name;

  /// How long a graceful [close] waits for the requests in flight.
  final Duration? closeTimeout;

  /// The requests the adapter is handling; the adapter tracks each request
  /// with [InFlightRequests.track].
  final InFlightRequests inFlight = InFlightRequests();

  final Completer<void> _forced = Completer<void>();
  S? _server;
  Future<void> Function(S server, {required bool force})? _stop;
  Future<void>? _binding;
  Future<void>? _closing;
  Future<void> _escalation = Future<void>.value();

  /// The bound server; `null` before [start] completed and after [close].
  S? get server => _closing == null ? _server : null;

  /// Binds a server with [bind], remembers it and starts [serve]ing.
  ///
  /// [stop] stops the server accepting connections; with `force` it also
  /// drops the open ones, without it the returned future may wait for them.
  /// Fails with a [StateError] when called after a successful start or after
  /// [close], and when [close] is called while [bind] is pending (the server
  /// is stopped then). When [bind] fails, the failure is passed on and
  /// [start] can be called again.
  Future<void> start(
    Future<S> Function() bind, {
    required Future<void> Function(S server, {required bool force}) stop,
    required void Function(S server) serve,
  }) async {
    if (_closing != null) throw StateError('$name is closed.');
    if (_binding != null) {
      throw StateError('$name.listen can be called only once.');
    }
    // Claimed before the await: a second start or a close that arrives
    // while the bind is pending must see it.
    final bound = Completer<void>();
    _binding = bound.future;
    var isServing = false;
    try {
      final server = await bind();
      if (_closing != null) {
        await stop(server, force: true);
        throw StateError('$name was closed while binding.');
      }
      _server = server;
      _stop = stop;
      serve(server);
      isServing = true;
    } finally {
      // A failed start leaves nothing bound: it can be retried (the
      // application passes the failure on and allows another listen).
      if (!isServing) _binding = null;
      bound.complete();
    }
  }

  /// Stops the server and, without [force], waits for the requests in
  /// flight; see the class documentation. Completes at once when [start]
  /// was never called.
  Future<void> close({required bool force}) {
    final closing = _closing;
    if (closing == null) return _closing = _shutdown(force: force);
    // A forced close escalates a graceful one that is still waiting.
    if (force && !_forced.isCompleted) _escalate();
    return closing;
  }

  void _escalate() {
    _forced.complete();
    final (server, stop) = (_server, _stop);
    if (server == null || stop == null) return;
    // A failure surfaces through the pending close; ignore() only keeps it
    // from being reported as unhandled while that close is not looking.
    _escalation = stop(server, force: true)..ignore();
  }

  Future<void> _shutdown({required bool force}) async {
    // A pending bind stops its own server once it sees the close.
    await _binding;
    final (server, stop) = (_server, _stop);
    if (server == null || stop == null) return;
    await stop(server, force: force);
    if (!force) await _drain(server, stop);
    await _escalation;
  }

  Future<void> _drain(
    S server,
    Future<void> Function(S server, {required bool force}) stop,
  ) {
    // A later close(force: true) ends the wait; it drops the connections.
    final wait = Future.any([inFlight.idle, _forced.future]);
    final limit = closeTimeout;
    if (limit == null) return wait;
    // Past the limit, drop the remaining connections as force does; their
    // requests stay counted, but nothing waits for them any more.
    return wait.timeout(limit, onTimeout: () => stop(server, force: true));
  }
}
