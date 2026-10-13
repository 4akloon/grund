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
  /// Creates the adapter. [closeTimeout] bounds how long a graceful
  /// `close` waits for the requests in flight. [onError] receives failures
  /// the adapter cannot turn into a response (a handler that throws, a body
  /// stream that fails mid-response, a broken connection); it defaults to
  /// [printError] and must not throw.
  IoAdapter({this.closeTimeout = defaultCloseTimeout, ErrorLogger? onError})
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
    io.stderr.writeln('dartnest_io: $error\n$stackTrace');
  }

  final InFlightRequests _inFlight = InFlightRequests();
  io.HttpServer? _server;
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
    if (_binding != null || _closing != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    // Claimed before the await: a second listen or a close that arrives
    // while the bind is pending must see it.
    final bound = Completer<void>();
    _binding = bound.future;
    try {
      final server = await io.HttpServer.bind(address, port);
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
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  Future<void> _shutdown({required bool force}) async {
    // A pending bind closes its own server once it sees the close.
    await _binding;
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
    if (force) return;
    final limit = closeTimeout;
    if (limit == null) return _inFlight.idle;
    // Past the limit, drop the remaining connections as force does; their
    // requests stay counted, but nothing waits for them any more.
    return _inFlight.idle.timeout(
      limit,
      onTimeout: () => server.close(force: true),
    );
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
      onError(error, stackTrace);
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
      onError(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }
}
