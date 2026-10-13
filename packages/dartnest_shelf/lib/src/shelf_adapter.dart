import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/adapter.dart';
import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'shelf_bridge.dart';

/// Serves a dartnest application through shelf on a `dart:io` server.
///
/// ```dart
/// final adapter = ShelfAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// ```
///
/// Use it to run shelf on the wire; to put an application into a shelf
/// pipeline you already have, use `shelfHandler(app)` instead.
///
/// The server adds no x-powered-by and no dart:io default headers (such as
/// `x-frame-options`; add them with middleware). It does not send exactly
/// the application's headers though: `shelf_io` itself adds a `date`
/// header. Like `shelf_io`, requests are routed on the requested URI that
/// shelf builds from `Host` and the target, whereas `IoAdapter` routes on
/// the request target only.
final class ShelfAdapter implements HttpAdapter {
  /// Creates the adapter. [closeTimeout] bounds how long a graceful
  /// `close` waits for the requests in flight. [onError] receives failures
  /// the adapter cannot turn into a response (a handler that throws, a body
  /// stream that fails mid-response); it defaults to [printError] and must
  /// not throw.
  ShelfAdapter({this.closeTimeout = defaultCloseTimeout, ErrorLogger? onError})
    : onError = onError ?? printError;

  /// The default [closeTimeout].
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// How long `close()` without `force` waits for the requests in flight,
  /// responses still being written included; then it drops the remaining
  /// connections as `close(force: true)` does and completes normally.
  /// `null` waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures.
  final ErrorLogger onError;

  /// The default [onError]: prints the error and stack trace to stderr.
  static void printError(Object error, StackTrace stackTrace) {
    io.stderr.writeln('dartnest_shelf: $error\n$stackTrace');
  }

  final InFlightRequests _inFlight = InFlightRequests();
  io.HttpServer? _server;
  final Completer<void> _forced = Completer<void>();
  Future<void>? _binding;
  Future<void>? _closing;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_server) {
    final server? when _closing == null => server.port,
    _ => throw StateError('ShelfAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_closing != null) throw StateError('ShelfAdapter is closed.');
    if (_binding != null) {
      throw StateError('ShelfAdapter.listen can be called only once.');
    }
    // Claimed before the await: a second listen or a close that arrives
    // while the bind is pending must see it.
    final bound = Completer<void>();
    _binding = bound.future;
    try {
      final server = await io.HttpServer.bind(address, port);
      if (_closing != null) {
        await server.close(force: true);
        throw StateError('ShelfAdapter was closed while binding.');
      }
      server.defaultResponseHeaders.clear();
      _server = server;
      final bridge = ShelfBridge(handler, onError: _report).call;
      server.listen(
        (request) => unawaited(_inFlight.track(() => _serve(request, bridge))),
      );
    } finally {
      bound.complete();
    }
  }

  @override
  Future<void> close({bool force = false}) {
    final closing = _closing;
    if (closing == null) return _closing = _shutdown(force: force);
    // A forced close escalates a graceful one that is still waiting.
    if (force && !_forced.isCompleted) {
      _forced.complete();
      unawaited(_server?.close(force: true));
    }
    return closing;
  }

  Future<void> _shutdown({required bool force}) async {
    // A pending bind closes its own server once it sees the close.
    await _binding;
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
    if (force) return;
    // A later close(force: true) ends the wait; it drops the connections.
    final wait = Future.any([_inFlight.idle, _forced.future]);
    final limit = closeTimeout;
    if (limit == null) return wait;
    // Past the limit, drop the remaining connections as force does; their
    // requests stay counted, but nothing waits for them any more.
    return wait.timeout(limit, onTimeout: () => server.close(force: true));
  }

  Future<void> _serve(io.HttpRequest request, shelf.Handler handler) async {
    // Response boundary: shelf_io writes the body stream (user code) to a
    // socket that can fail; the connection is already dropped, so report.
    try {
      await shelf_io.handleRequest(request, handler, poweredByHeader: null);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    // Reporter boundary: onError is user code; a failing reporter must not
    // stop the 500 or crash the server, so its failure goes to stderr.
    try {
      onError(error, stackTrace);
    } on Object catch (reporterError) {
      io.stderr.writeln('dartnest_shelf: onError failed: $reporterError');
    }
  }
}
