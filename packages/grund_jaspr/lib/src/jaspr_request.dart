import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

/// Builds the shelf [Request] Jaspr renders from: the method, the path and
/// query, and every header value of a grund request.
///
/// Jaspr reads only the URL, the handler path and the headers, so the body
/// is not passed. The host of the URL is a placeholder; the real one is in
/// the `host` header. Several `cookie` header lines (HTTP/2 allows them)
/// are joined with `; `, as RFC 9113 says, not with the `,` Jaspr uses for
/// other headers.
abstract final class JasprRequest {
  /// The Jaspr request for [request].
  static Request from(HttpRequest request) => Request(
    request.method,
    Uri(
      scheme: 'http',
      host: 'localhost',
      path: request.uri.path.isEmpty ? '/' : request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    ),
    headers: {
      for (final name in request.headers.names)
        name: _values(request.headers, name),
    },
    handlerPath: '/',
  );

  static List<String> _values(HeaderMap headers, String name) {
    final values = headers.all(name);
    return name == 'cookie' ? [values.join('; ')] : values;
  }
}
