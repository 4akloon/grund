import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A response received through `HttpClient`, with the whole body read.
final class ClientResponse {
  /// Creates the response.
  ClientResponse({
    required this.status,
    required this.headers,
    required this.bytes,
    required this.localPort,
  });

  /// Reads [response] to the end.
  static Future<ClientResponse> read(HttpClientResponse response) async {
    final body = BytesBuilder(copy: false);
    await response.forEach(body.add);
    return ClientResponse(
      status: response.statusCode,
      headers: response.headers,
      bytes: body.takeBytes(),
      localPort: response.connectionInfo?.localPort ?? 0,
    );
  }

  /// Status code.
  final int status;

  /// Response headers as `dart:io` parsed them.
  final HttpHeaders headers;

  /// The body.
  final Uint8List bytes;

  /// The client-side port of the connection the response came on.
  final int localPort;

  /// [bytes] decoded as UTF-8.
  String get text => utf8.decode(bytes);

  /// [text] decoded as JSON.
  Object? get json => jsonDecode(text);
}
