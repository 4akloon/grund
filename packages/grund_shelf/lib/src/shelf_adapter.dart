import 'dart:async';
import 'dart:io' as io;

import 'package:grund_http/adapter.dart';
import 'package:grund_http/grund_http.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'guarded_reporter.dart';
import 'shelf_bridge.dart';
import 'target_request.dart';

/// Serves a grund application through shelf on a `dart:io` server.
///
/// ```dart
/// // The root module imports HttpModule and ShelfAdapterModule.
/// final app = App(root: const AppModule());
/// await app.start();
/// final adapter = app.container.root<HttpAdapter>() as ShelfAdapter;
/// print('listening on ${adapter.port}');
/// ```
///
/// Use it to run shelf on the wire; to put an application into a shelf
/// pipeline you already have, use `shelfHandler(app)` instead.
///
/// The server adds no `x-powered-by` and no dart:io default headers (such as
/// `x-frame-options`; add them with middleware). It does not send exactly
/// the application's headers though: `shelf_io` itself adds a `date`
/// header. Requests are routed on their target only, like `IoAdapter`
/// does: unlike plain `shelf_io`, neither `Host` nor the client-controlled
/// `X-Forwarded-Host` / `X-Forwarded-Proto` headers can change the routed
/// path.
final class ShelfAdapter implements HttpAdapter {
  /// Creates the adapter. [closeTimeout] bounds how long a graceful
  /// `close` waits for the requests in flight. [onError] receives failures
  /// the adapter cannot turn into a response (a handler that throws, a body
  /// stream that fails mid-response); it defaults to [printError]. If
  /// [onError] throws, the adapter keeps serving and that failure goes to
  /// stderr with its stack trace.
  ShelfAdapter({this.closeTimeout = defaultCloseTimeout, ErrorLogger? onError})
    : onError = onError ?? printError,
      _report = GuardedReporter(onError ?? printError),
      _lifecycle = AdapterLifecycle(
        name: 'ShelfAdapter',
        closeTimeout: closeTimeout,
      );

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
    io.stderr.writeln('grund_shelf: $error\n$stackTrace');
  }

  final AdapterLifecycle<io.HttpServer> _lifecycle;
  final GuardedReporter _report;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_lifecycle.server) {
    final server? => server.port,
    _ => throw StateError('ShelfAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) {
    final bridge = ShelfBridge(handler, onError: _report.call).call;
    return _lifecycle.start(
      () => _bind(address, port),
      stop: (server, {required force}) => server.close(force: force),
      serve: (server) => server.listen(
        (request) =>
            unawaited(_lifecycle.inFlight.track(() => _serve(request, bridge))),
      ),
    );
  }

  Future<io.HttpServer> _bind(Object address, int port) async {
    final server = await io.HttpServer.bind(address, port);
    server.defaultResponseHeaders.clear();
    return server;
  }

  @override
  Future<void> close({bool force = false}) => _lifecycle.close(force: force);

  Future<void> _serve(io.HttpRequest request, shelf.Handler handler) async {
    // Response boundary: shelf_io writes the body stream (user code) to a
    // socket that can fail; report the failure and drop the connection
    // (dart:io only drops it itself once the head was sent).
    try {
      await shelf_io.handleRequest(
        TargetRequest(request),
        handler,
        poweredByHeader: null,
      );
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      await _dropConnection(request);
    }
  }

  // A response whose head could not be written (an invalid header value, a
  // body stream somebody already listens to) is never completed, so dart:io
  // keeps the connection open: the client hangs and close() waits for it.
  static Future<void> _dropConnection(io.HttpRequest request) async {
    try {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    } on StateError {
      // The head was sent: dart:io has already dropped the connection.
    }
  }
}
