import 'connection_info.dart';
import 'header_map.dart';
import 'request_body.dart';

/// An incoming HTTP request, independent of any server library.
///
/// Adapters build it from their native request; tests build it directly or
/// through `TestClient`. It is immutable: [headers] is read-only and
/// [method] is upper-cased.
final class HttpRequest {
  /// Creates a request. [uri] is the request target: a path with an
  /// optional query (`/users?page=2`); an absolute URI also works.
  HttpRequest({
    required String method,
    required this.uri,
    HeaderMap? headers,
    RequestBody? body,
    this.connectionInfo,
  }) : method = method.toUpperCase(),
       headers = HeaderMap.unmodifiable(headers ?? HeaderMap()),
       body = body ?? RequestBody.empty();

  /// Upper-cased method, for example `GET`.
  final String method;

  /// Request target: path (percent-decoded via [Uri.pathSegments]) and query.
  final Uri uri;

  /// Read-only request headers.
  final HeaderMap headers;

  /// The body, read lazily.
  final RequestBody body;

  /// Client connection details, when the adapter provides them.
  final ConnectionInfo? connectionInfo;

  @override
  String toString() => 'HttpRequest($method $uri)';
}
