import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/adapter.dart';
import 'package:dartnest/dartnest.dart';

import 'io_request_mapper.dart';
import 'io_response_writer.dart';

/// Serves a dartnest application on a `dart:io` [io.HttpServer].
///
/// ```dart
/// final adapter = IoAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// print('listening on ${adapter.port}');
/// ```
///
/// The server adds no x-powered-by and no dart:io default headers (such as
/// `x-frame-options`; add them with middleware). Requests are routed on
/// their target only, never on `Host`.
final class IoAdapter implements HttpAdapter {
  /// Creates the adapter; with [securityContext] it serves HTTPS.
  /// [closeTimeout] bounds how long a graceful `close` waits for the
  /// requests in flight. [onError] receives failures the adapter cannot
  /// turn into a response (a handler that throws, a body stream that fails
  /// mid-response, a broken connection); it defaults to [printError] and
  /// must not throw.
  IoAdapter({
    this.securityContext,
    this.closeTimeout = defaultCloseTimeout,
    ErrorLogger? onError,
  }) : onError = onError ?? printError;

  /// The default [closeTimeout].
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// TLS configuration; `null` serves plain HTTP.
  final io.SecurityContext? securityContext;

  /// How long `close()` without `force` waits for the requests in flight,
  /// responses still being written included; then it drops the remaining
  /// connections as `close(force: true)` does and completes normally.
  /// `null` waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures.
  final ErrorLogger onError;

  /// The default [onError]: prints the error and stack trace to stderr.
  static void printError(Object error, StackTrace stackTrace) {
    io.stderr.writeln('dartnest_io: $error\n$stackTrace');
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
    _ => throw StateError('IoAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_closing != null) throw StateError('IoAdapter is closed.');
    if (_binding != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    // Claimed before the await: a second listen or a close that arrives
    // while the bind is pending must see it.
    final bound = Completer<void>();
    _binding = bound.future;
    try {
      final context = securityContext;
      final server = context == null
          ? await io.HttpServer.bind(address, port)
          : await io.HttpServer.bindSecure(address, port, context);
      if (_closing != null) {
        await server.close(force: true);
        throw StateError('IoAdapter was closed while binding.');
      }
      server.defaultResponseHeaders.clear();
      _server = server;
      server.listen(
        (request) => unawaited(_inFlight.track(() => _serve(request, handler))),
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

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await _answer(native, handler);
    // Response boundary: the body stream is user code and the client can
    // go away; dart:io has already dropped the connection, so report it.
    try {
      await IoResponseWriter.write(
        response,
        native.response,
        isHead: native.method == 'HEAD',
      );
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  Future<HttpResponse> _answer(
    io.HttpRequest native,
    RequestHandler handler,
  ) async {
    // Request boundary: Application.handle only fails when the
    // application's own error logger throws; answer 500 without a body
    // and keep serving.
    try {
      return await handler(IoRequestMapper.map(native));
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    // Reporter boundary: onError is user code; a failing reporter must not
    // stop the 500 or crash the server, so its failure goes to stderr.
    try {
      onError(error, stackTrace);
    } on Object catch (reporterError) {
      io.stderr.writeln('dartnest_io: onError failed: $reporterError');
    }
  }
}
