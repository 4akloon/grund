import 'dart:convert';

import '../app/application.dart';
import '../http/header_map.dart';
import '../http/http_request.dart';
import '../http/request_body.dart';
import 'test_response.dart';

/// Sends requests straight to [Application.handle], without a server.
///
/// ```dart
/// final client = TestClient(app);
/// final response = await client.get('/users/1');
/// expect(response.json, {'id': 1, 'name': 'ann'});
/// ```
final class TestClient {
  /// Creates a client for [app].
  TestClient(this.app);

  /// The application under test.
  final Application app;

  /// Sends `GET` to [target] (a path with an optional query).
  Future<TestResponse> get(
    String target, {
    Map<String, String> headers = const {},
  }) => request('GET', target, headers: headers);

  /// Sends `DELETE` to [target].
  Future<TestResponse> delete(
    String target, {
    Map<String, String> headers = const {},
  }) => request('DELETE', target, headers: headers);

  /// Sends `POST` to [target] with [json] encoded as the body.
  Future<TestResponse> post(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('POST', target, json: json, headers: headers);

  /// Sends `PUT` to [target] with [json] encoded as the body.
  Future<TestResponse> put(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('PUT', target, json: json, headers: headers);

  /// Sends `PATCH` to [target] with [json] encoded as the body.
  Future<TestResponse> patch(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('PATCH', target, json: json, headers: headers);

  /// Sends [method] to [target]. The body is [json] encoded as JSON (with
  /// `content-type: application/json`) or the raw [body] string; passing
  /// both is an `ArgumentError`. `json: null` cannot be sent: null means no
  /// body. A response to `HEAD` keeps its body here, unlike real adapters,
  /// which drop it.
  Future<TestResponse> request(
    String method,
    String target, {
    Object? json,
    String? body,
    Map<String, String> headers = const {},
  }) {
    if (json != null && body != null) {
      throw ArgumentError('Pass either json or body, not both.');
    }
    final requestHeaders = HeaderMap.of(headers);
    final text = json == null ? body : jsonEncode(json);
    if (json != null && requestHeaders['content-type'] == null) {
      requestHeaders.set('content-type', 'application/json');
    }
    return send(
      HttpRequest(
        method: method,
        uri: Uri.parse(target),
        headers: requestHeaders,
        body: text == null ? null : RequestBody.bytes(utf8.encode(text)),
      ),
    );
  }

  /// Sends a prepared [request] and reads the whole response body.
  Future<TestResponse> send(HttpRequest request) async {
    final response = await app.handle(request);
    return TestResponse(
      status: response.status,
      headers: response.headers,
      bytes: await response.body.readAll(),
    );
  }
}
