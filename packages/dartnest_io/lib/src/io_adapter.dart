import 'dart:async';
import 'dart:io' as io;

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
  /// Creates the adapter.
  IoAdapter();

  io.HttpServer? _server;
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
    if (_server != null || _closing != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    final server = await io.HttpServer.bind(address, port);
    server.defaultResponseHeaders.clear();
    _server = server;
    server.listen((request) => unawaited(_serve(request, handler)));
  }

  @override
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  Future<void> _shutdown({required bool force}) async {
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
  }

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await handler(IoRequestMapper.map(native));
    await IoResponseWriter.write(
      response,
      native.response,
      isHead: native.method == 'HEAD',
    );
  }
}
