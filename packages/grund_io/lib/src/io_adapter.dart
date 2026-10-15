import 'dart:async';
import 'dart:io' as io;

import 'package:grund_http/adapter.dart';
import 'package:grund_http/grund_http.dart';

import 'io_request_mapper.dart';
import 'io_response_writer.dart';

/// Serves a grund application on a `dart:io` [io.HttpServer].
///
/// ```dart
/// // The root module imports HttpModule and IoAdapterModule.
/// final app = App(root: const AppModule());
/// await app.start();
/// final adapter = app.container.root<HttpAdapter>() as IoAdapter;
/// print('listening on ${adapter.port}');
/// ```
///
/// With a [securityContext] it serves HTTPS.
///
/// The server adds no `x-powered-by` and no dart:io default headers (such as
/// `x-frame-options`; add them with middleware). Requests are routed on
/// their target only, never on `Host`.
final class IoAdapter implements HttpAdapter {
  /// Creates the adapter; with [securityContext] it serves HTTPS.
  /// [closeTimeout] bounds how long a graceful `close` waits for the
  /// requests in flight. [onError] receives failures the adapter cannot
  /// turn into a response (a handler that throws, a body stream that fails
  /// mid-response, a broken connection); it defaults to [printError]. If
  /// [onError] throws, the adapter keeps serving and that failure goes to
  /// stderr with its stack trace.
  IoAdapter({
    this.securityContext,
    this.closeTimeout = defaultCloseTimeout,
    ErrorLogger? onError,
  }) : onError = onError ?? printError,
       _lifecycle = AdapterLifecycle(
         name: 'IoAdapter',
         closeTimeout: closeTimeout,
       );

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
    io.stderr.writeln('grund_io: $error\n$stackTrace');
  }

  final AdapterLifecycle<io.HttpServer> _lifecycle;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_lifecycle.server) {
    final server? => server.port,
    _ => throw StateError('IoAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) => _lifecycle.start(
    () => _bind(address, port),
    stop: (server, {required force}) => server.close(force: force),
    serve: (server) => server.listen(
      (request) =>
          unawaited(_lifecycle.inFlight.track(() => _serve(request, handler))),
    ),
  );

  Future<io.HttpServer> _bind(Object address, int port) async {
    final context = securityContext;
    final server = context == null
        ? await io.HttpServer.bind(address, port)
        : await io.HttpServer.bindSecure(address, port, context);
    server.defaultResponseHeaders.clear();
    return server;
  }

  @override
  Future<void> close({bool force = false}) => _lifecycle.close(force: force);

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await _answer(native, handler);
    // Response boundary: the body stream is user code and the client can
    // go away; report the failure and drop the connection (dart:io only
    // drops it itself once the head was sent).
    try {
      await IoResponseWriter.write(
        response,
        native.response,
        isHead: native.method == 'HEAD',
      );
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      await _dropConnection(native);
    }
  }

  // A response whose head could not be written (an invalid header value, a
  // body stream somebody already listens to) is never completed, so dart:io
  // keeps the connection open: the client hangs and close() waits for it.
  static Future<void> _dropConnection(io.HttpRequest native) async {
    try {
      final socket = await native.response.detachSocket(writeHeaders: false);
      socket.destroy();
    } on StateError {
      // The head was sent: dart:io has already dropped the connection.
    }
  }

  Future<HttpResponse> _answer(
    io.HttpRequest native,
    RequestHandler handler,
  ) async {
    // Request boundary: the HttpServer request handler only fails
    // when the application's own error logger throws; answer 500 without a body
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
    } on Object catch (reporterError, reporterStackTrace) {
      io.stderr.writeln(
        'grund_io: onError failed: $reporterError\n$reporterStackTrace',
      );
    }
  }
}
