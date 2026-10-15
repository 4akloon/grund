import 'dart:convert';
import 'dart:typed_data';

import '../http/header_map.dart';
import '../http/http_response.dart';
import '../http/response_body.dart';
import '../http/response_head.dart';
import '../http/status_code.dart';
import 'pipeline_error.dart';
import 'serializer_registry.dart';

/// Turns a handler (or filter) result into an [HttpResponse].
///
/// | Result | Response |
/// | --- | --- |
/// | [HttpResponse] | as is, plus head headers it does not set |
/// | `null` | 204, empty |
/// | [String] | `text/plain; charset=utf-8` |
/// | [Uint8List] | `application/octet-stream` |
/// | `Stream<List<int>>` | streamed `application/octet-stream` |
/// | anything else | JSON (`Map`, `List` (also `List<int>`), `num`, `bool`, objects with `toJson()`, registered types) |
///
/// The [ResponseHead] status replaces the default status (200, or 204 for
/// `null`), and its headers replace the defaults. A value JSON cannot encode
/// throws [SerializationError].
final class ResponseSerializer {
  /// Creates a serializer using [registry] for types without `toJson()`.
  const ResponseSerializer(this.registry);

  /// Converters for types without `toJson()`.
  final SerializerRegistry registry;

  /// Serializes [result] with the status and headers in [head].
  HttpResponse serialize(Object? result, ResponseHead head) => switch (result) {
    HttpResponse() => result.mergeHeaders(head.headers),
    null => _build(head, StatusCode.noContent, null, BytesBody(const [])),
    String() => _build(
      head,
      StatusCode.ok,
      'text/plain; charset=utf-8',
      BytesBody(utf8.encode(result)),
    ),
    Uint8List() => _build(
      head,
      StatusCode.ok,
      'application/octet-stream',
      BytesBody(result),
    ),
    Stream<List<int>>() => _build(
      head,
      StatusCode.ok,
      'application/octet-stream',
      StreamBody(result),
    ),
    _ => _build(
      head,
      StatusCode.ok,
      'application/json; charset=utf-8',
      BytesBody(utf8.encode(_encode(result))),
    ),
  };

  HttpResponse _build(
    ResponseHead head,
    int defaultStatus,
    String? contentType,
    ResponseBody body,
  ) {
    final headers = HeaderMap();
    if (contentType != null) headers.set('content-type', contentType);
    headers.setAll(head.headers);
    return HttpResponse(
      head.status ?? defaultStatus,
      headers: headers,
      body: body,
    );
  }

  String _encode(Object value) {
    // ResponseSerializer boundary: jsonEncode calls toJson() itself and
    // signals an unencodable user value with this SDK Error; it is converted
    // to the documented SerializationError with the original stack trace.
    try {
      return jsonEncode(registry.prepare(value));
    } on JsonUnsupportedObjectError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SerializationError(
          valueType: error.unsupportedObject.runtimeType,
          cause: error.cause,
        ),
        stackTrace,
      );
    }
  }
}
