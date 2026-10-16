import 'dart:convert';
import 'dart:typed_data';

import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/problem_code.dart';
import '../http/request_body.dart';
import 'form_decoder.dart';

/// Reads the body of one request once, within a size limit, and decodes it.
final class BodyReader {
  /// Creates the reader for [request]; [maxBytes] is the limit, `null` for
  /// none.
  BodyReader(this._request, this._maxBytes);

  final HttpRequest _request;
  final int? _maxBytes;
  Future<Uint8List>? _bytes;
  Future<Object?>? _json;
  Future<Map<String, List<String>>>? _form;

  /// The raw body; throws [PayloadTooLargeException] (413) as soon as the
  /// declared or the received size exceeds the limit.
  Future<Uint8List> bytes() => _bytes ??= _read();

  /// The body decoded as one JSON object and built with [fromJson].
  Future<T> object<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) async {
    final json = await _decoded();
    if (json is! Map<String, Object?>) {
      throw _invalid('Request body must be a JSON object.');
    }
    return _build(json, fromJson, ProblemCode.bodyPointer);
  }

  /// The body decoded as a JSON array of objects, each built with
  /// [fromJson].
  Future<List<T>> list<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) async {
    final json = await _decoded();
    if (json is! List<Object?>) {
      throw _invalid('Request body must be a JSON array.');
    }
    return [
      for (final (index, item) in json.indexed)
        if (item is Map<String, Object?>)
          _build(item, fromJson, '${ProblemCode.bodyPointer}/$index')
        else
          throw _invalid(
            'Item $index of the request body must be a JSON object.',
            pointer: '${ProblemCode.bodyPointer}/$index',
          ),
    ];
  }

  /// The body decoded as form fields; a body that is not UTF-8 or has a
  /// bad escape is a 400 `body_invalid`.
  Future<Map<String, List<String>>> form() =>
      _form ??= bytes().then(_decodeForm);

  Future<Object?> _decoded() =>
      _json ??= bytes().then((data) => RequestBody.bytes(data).json());

  T _build<T extends Object>(
    Map<String, Object?> json,
    T Function(Map<String, Object?> json) fromJson,
    String pointer,
  ) {
    // fromJson is user code and signals a missing or mistyped field with a
    // FormatException or with the TypeError of a failed cast (an Error the
    // language throws for user data); both are the client's fault and become
    // a 400. Any other failure is a bug and propagates.
    try {
      return fromJson(json);
    } on FormatException catch (error) {
      throw _invalid(
        'Invalid request body: ${error.message}',
        pointer: pointer,
      );
    } on TypeError {
      throw _invalid(
        'Invalid request body: a field is missing or has the wrong type.',
        pointer: pointer,
      );
    }
  }

  static Map<String, List<String>> _decodeForm(Uint8List data) {
    try {
      return FormDecoder.decode(utf8.decode(data));
    } on FormatException catch (error) {
      throw _invalid('Invalid form body: ${error.message}');
    }
  }

  Future<Uint8List> _read() async {
    final limit = _maxBytes;
    if (limit == null) return _request.body.bytes();
    final declared = int.tryParse(_request.headers['content-length'] ?? '');
    if (declared != null && declared > limit) throw _tooLarge(limit);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _request.body.stream) {
      builder.add(chunk);
      if (builder.length > limit) throw _tooLarge(limit);
    }
    return builder.takeBytes();
  }

  static PayloadTooLargeException _tooLarge(int limit) =>
      PayloadTooLargeException(
        message: 'Request body is larger than $limit bytes.',
        code: ProblemCode.bodyTooLarge,
      );

  static BadRequestException _invalid(String message, {String? pointer}) =>
      BadRequestException(
        message: message,
        code: ProblemCode.bodyInvalid,
        pointer: pointer ?? ProblemCode.bodyPointer,
      );
}
