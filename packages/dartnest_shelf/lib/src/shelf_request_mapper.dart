import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Builds the dartnest [HttpRequest] for a shelf request.
abstract final class ShelfRequestMapper {
  /// The context key under which `shelf_io` stores the connection details.
  static const connectionInfoKey = 'shelf.io.connection_info';

  /// The request for [request]: its method; its path relative to the
  /// shelf `handlerPath` (so a mounted application sees its own paths)
  /// with the raw query; every header value; the unread body; the client
  /// address when `shelf_io` serves it.
  static HttpRequest map(shelf.Request request) {
    final headers = HeaderMap();
    for (final MapEntry(:key, :value) in request.headersAll.entries) {
      for (final single in value) {
        headers.add(key, single);
      }
    }
    final url = request.url;
    return HttpRequest(
      method: request.method,
      uri: Uri(path: '/${url.path}', query: url.hasQuery ? url.query : null),
      headers: headers,
      body: RequestBody(request.read()),
      connectionInfo: switch (request.context[connectionInfoKey]) {
        final io.HttpConnectionInfo info => ConnectionInfo(
          remoteAddress: info.remoteAddress.address,
          remotePort: info.remotePort,
        ),
        _ => null,
      },
    );
  }
}
