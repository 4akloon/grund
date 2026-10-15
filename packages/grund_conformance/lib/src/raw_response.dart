import 'dart:convert';
import 'dart:typed_data';

import 'package:grund/grund.dart';

/// A response read byte for byte from a socket by `RawHttp`: what
/// `HttpClient` hides (the exact header lines, the bytes after a `HEAD`
/// response, a chunked body that never ended).
final class RawResponse {
  RawResponse._({
    required this.bytes,
    required this.status,
    required this.headers,
    required this.body,
    required this.isComplete,
  });

  /// Parses the first response in [bytes]. Without a complete head the
  /// status is 0 and the response is incomplete.
  factory RawResponse.parse(Uint8List bytes) {
    final headEnd = _indexOf(bytes, const [13, 10, 13, 10]);
    if (headEnd < 0) {
      return RawResponse._(
        bytes: bytes,
        status: 0,
        headers: HeaderMap(),
        body: Uint8List(0),
        isComplete: false,
      );
    }
    final lines = latin1.decode(bytes.sublist(0, headEnd)).split('\r\n');
    final headers = HeaderMap();
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      headers.add(
        line.substring(0, colon).trim(),
        line.substring(colon + 1).trim(),
      );
    }
    final rest = bytes.sublist(headEnd + 4);
    final (body, isComplete) = _readBody(rest, headers);
    return RawResponse._(
      bytes: bytes,
      status: int.parse(lines.first.split(' ')[1]),
      headers: headers,
      body: body,
      isComplete: isComplete,
    );
  }

  /// Everything the server sent before closing the connection.
  final Uint8List bytes;

  /// Status code of the first response; 0 without a complete head.
  final int status;

  /// Header lines of the first response; a line without a colon is skipped
  /// (folded continuation lines are not supported).
  final HeaderMap headers;

  /// The body after content-length or chunked decoding.
  final Uint8List body;

  /// Whether the body ended as its framing promised.
  final bool isComplete;

  /// [body] decoded as UTF-8.
  String get text => utf8.decode(body);

  /// [text] decoded as JSON.
  Object? get json => jsonDecode(text);

  static (Uint8List, bool) _readBody(Uint8List rest, HeaderMap headers) {
    if (headers['transfer-encoding'] == 'chunked') return _dechunk(rest);
    final length = int.tryParse(headers['content-length'] ?? '');
    if (length == null) return (rest, true);
    if (rest.length < length) return (rest, false);
    return (rest.sublist(0, length), true);
  }

  static (Uint8List, bool) _dechunk(Uint8List data) {
    final body = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final lineEnd = _indexOf(data, const [13, 10], offset);
      if (lineEnd < 0) return (body.takeBytes(), false);
      final sizeText = latin1.decode(data.sublist(offset, lineEnd));
      final size = int.parse(sizeText.split(';').first.trim(), radix: 16);
      if (size == 0) return (body.takeBytes(), true);
      final start = lineEnd + 2;
      if (data.length < start + size + 2) return (body.takeBytes(), false);
      body.add(data.sublist(start, start + size));
      offset = start + size + 2;
    }
  }

  static int _indexOf(Uint8List data, List<int> pattern, [int from = 0]) {
    for (var i = from; i <= data.length - pattern.length; i++) {
      var matches = true;
      for (var j = 0; j < pattern.length && matches; j++) {
        matches = data[i + j] == pattern[j];
      }
      if (matches) return i;
    }
    return -1;
  }
}
