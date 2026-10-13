import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

/// Writes a dartnest [HttpResponse] to a `dart:io` response.
abstract final class IoResponseWriter {
  /// Writes [response] to [native] and closes it.
  ///
  /// - Every header value is copied except `transfer-encoding`: framing
  ///   is the writer's job (`content-length` for bytes, chunked for a
  ///   stream without `content-length`).
  /// - A stream is written chunk by chunk, unbuffered, so each chunk
  ///   reaches the client when the stream emits it.
  /// - For `HEAD` ([isHead]) no body is written and a stream is cancelled
  ///   unread; the headers stay those of the `GET` response.
  ///
  /// Fails when the body stream fails or the connection breaks; the caller
  /// reports it, `dart:io` has already dropped the connection.
  static Future<void> write(
    HttpResponse response,
    io.HttpResponse native, {
    required bool isHead,
  }) async {
    native.statusCode = response.status;
    for (final name in response.headers.names) {
      if (name == io.HttpHeaders.transferEncodingHeader) continue;
      native.headers.set(name, response.headers.all(name));
    }
    switch (response.body) {
      case BytesBody(:final bytes):
        native.contentLength = bytes.length;
        if (!isHead) native.add(bytes);
      case StreamBody(:final stream) when isHead:
        await stream.listen(null).cancel();
      case StreamBody(:final stream):
        native.bufferOutput = false;
        await native.addStream(stream);
    }
    await native.close();
  }
}
