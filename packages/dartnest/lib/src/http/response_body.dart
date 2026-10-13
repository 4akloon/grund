import 'dart:typed_data';

/// The body of an `HttpResponse`: bytes in memory or a stream.
sealed class ResponseBody {
  /// Creates a body.
  const ResponseBody();

  /// Collects the whole body (for tests and small responses).
  Future<Uint8List> readAll() async {
    switch (this) {
      case BytesBody(:final bytes):
        return bytes;
      case StreamBody(:final stream):
        final builder = BytesBuilder(copy: false);
        await for (final chunk in stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
    }
  }
}

/// A body held in memory.
final class BytesBody extends ResponseBody {
  /// Wraps [bytes]; copies them unless they already are a [Uint8List].
  BytesBody(List<int> bytes)
    : bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  /// The content.
  final Uint8List bytes;
}

/// A body written chunk by chunk as the stream emits.
final class StreamBody extends ResponseBody {
  /// Wraps [stream]; it is listened to once, by the adapter.
  const StreamBody(this.stream);

  /// The content.
  final Stream<List<int>> stream;
}
