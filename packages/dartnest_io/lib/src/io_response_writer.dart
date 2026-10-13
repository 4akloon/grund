import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

/// Writes a dartnest [HttpResponse] to a `dart:io` response.
abstract final class IoResponseWriter {
  /// Writes [response] to [native] and closes it: status, every header
  /// value, then the bytes (with `content-length`) or the stream.
  static Future<void> write(
    HttpResponse response,
    io.HttpResponse native,
  ) async {
    native.statusCode = response.status;
    for (final name in response.headers.names) {
      native.headers.set(name, response.headers.all(name));
    }
    switch (response.body) {
      case BytesBody(:final bytes):
        native.contentLength = bytes.length;
        native.add(bytes);
      case StreamBody(:final stream):
        await native.addStream(stream);
    }
    await native.close();
  }
}
