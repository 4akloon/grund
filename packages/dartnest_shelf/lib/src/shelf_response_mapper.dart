import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Builds the shelf response for a dartnest [HttpResponse].
abstract final class ShelfResponseMapper {
  /// The context key that tells `shelf_io` whether to buffer the body.
  static const bufferOutputKey = 'shelf.io.buffer_output';

  /// The shelf response for [response].
  ///
  /// - Every header value is copied except `transfer-encoding`: shelf
  ///   would treat the body as already chunk-encoded.
  /// - Bytes get `content-length`; a stream is chunked unless the
  ///   application set `content-length`, and is not buffered by
  ///   `shelf_io`, so each chunk reaches the client when it is emitted.
  /// - For `HEAD` ([isHead]) the body is empty and `content-length` of a
  ///   bytes body is kept; a stream body is not read (the caller cancels
  ///   it).
  static shelf.Response map(HttpResponse response, {required bool isHead}) {
    final headers = <String, Object>{
      for (final name in response.headers.names)
        if (name != 'transfer-encoding') name: response.headers.all(name),
    };
    switch (response.body) {
      case BytesBody(:final bytes) when isHead:
        headers['content-length'] = '${bytes.length}';
        return shelf.Response(response.status, headers: headers);
      case BytesBody(:final bytes):
        return shelf.Response(response.status, body: bytes, headers: headers);
      case StreamBody() when isHead:
        return shelf.Response(
          response.status,
          body: const Stream<List<int>>.empty(),
          headers: headers,
        );
      case StreamBody(:final stream):
        return shelf.Response(
          response.status,
          body: stream,
          headers: headers,
          context: {bufferOutputKey: false},
        );
    }
  }
}
