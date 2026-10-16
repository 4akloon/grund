import 'dart:convert';

/// A response read whole by `LoopbackServer.send`.
final class ApiResponse {
  /// Creates the response.
  ApiResponse(
    this.status,
    this.headers,
    this.body, {
    this.setCookies = const [],
  });

  /// The status code.
  final int status;

  /// The first value of every header, by lowercase name.
  final Map<String, String> headers;

  /// Every `set-cookie` value, in order.
  final List<String> setCookies;

  /// The body as text.
  final String body;

  /// The body decoded as JSON.
  Object? get json => jsonDecode(body);

  @override
  String toString() => 'ApiResponse($status, $body)';
}
