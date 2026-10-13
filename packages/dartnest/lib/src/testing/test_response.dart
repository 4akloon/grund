import 'dart:convert';
import 'dart:typed_data';

import '../http/header_map.dart';

/// A fully read response returned by `TestClient`.
final class TestResponse {
  /// Creates a response with an already collected body.
  TestResponse({
    required this.status,
    required this.headers,
    required this.bytes,
  });

  /// Status code.
  final int status;

  /// Response headers.
  final HeaderMap headers;

  /// The whole body.
  final Uint8List bytes;

  /// The body decoded as UTF-8 (malformed bytes are replaced).
  String get text => utf8.decode(bytes, allowMalformed: true);

  /// The body decoded as JSON; throws `FormatException` if it is not JSON.
  Object? get json => jsonDecode(text);

  @override
  String toString() => 'TestResponse($status, $text)';
}
