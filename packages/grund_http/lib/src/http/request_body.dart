import 'dart:convert';
import 'dart:typed_data';

import 'http_exception.dart';
import 'problem_code.dart';

/// The body of an `HttpRequest`: a byte stream that is read at most once.
///
/// [bytes], [text] and [json] read the whole stream on first use and cache
/// the result, so a guard and a handler can both call `json()`. [stream]
/// hands out the raw stream for large uploads; after that the cached
/// readers fail with a [StateError], and vice versa only the cached bytes
/// are streamed.
final class RequestBody {
  /// Wraps a body stream supplied by an adapter.
  RequestBody(Stream<List<int>> source) : _source = source;

  /// A body whose content is already in memory (tests, middleware).
  RequestBody.bytes(List<int> bytes)
    : _source = null,
      _bytes = Future.value(Uint8List.fromList(bytes));

  /// A body with no content.
  RequestBody.empty() : this.bytes(const []);

  Stream<List<int>>? _source;
  Future<Uint8List>? _bytes;
  Future<Object?>? _json;
  bool _streamTaken = false;

  /// The whole body; read once and cached.
  Future<Uint8List> bytes() {
    if (_streamTaken) {
      throw StateError('The request body was already taken by `stream`.');
    }
    return _bytes ??= _collect();
  }

  /// The body decoded as UTF-8; malformed UTF-8 throws
  /// [BadRequestException].
  Future<String> text() async {
    final data = await bytes();
    try {
      return utf8.decode(data);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Request body is not valid UTF-8: ${error.message}',
        code: ProblemCode.bodyInvalid,
        pointer: ProblemCode.bodyPointer,
      );
    }
  }

  /// The body decoded as JSON and cached. An empty or malformed body throws
  /// [BadRequestException].
  Future<Object?> json() => _json ??= _decodeJson();

  /// The raw body stream; can be taken once, and not after [bytes] started
  /// reading (then the cached bytes are streamed instead).
  Stream<List<int>> get stream {
    final cached = _bytes;
    if (cached != null) return Stream.fromFuture(cached);
    final source = _source;
    if (source == null || _streamTaken) {
      throw StateError('The request body stream can be taken only once.');
    }
    _streamTaken = true;
    return source;
  }

  Future<Object?> _decodeJson() async {
    final source = await text();
    if (source.trim().isEmpty) {
      throw const BadRequestException(
        message: 'Request body is empty; expected JSON.',
        code: ProblemCode.bodyInvalid,
        pointer: ProblemCode.bodyPointer,
      );
    }
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Request body is not valid JSON: ${error.message}',
        code: ProblemCode.bodyInvalid,
        pointer: ProblemCode.bodyPointer,
      );
    }
  }

  Future<Uint8List> _collect() async {
    final source = _source;
    _source = null;
    if (source == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
