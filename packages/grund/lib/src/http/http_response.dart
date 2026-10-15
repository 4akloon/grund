import 'dart:convert';

import 'header_map.dart';
import 'response_body.dart';
import 'status_code.dart';

/// An outgoing HTTP response, independent of any server library.
///
/// Immutable: [headers] is read-only. Return it from a handler to control
/// the response completely, or return a plain value and let grund
/// serialize it.
final class HttpResponse {
  /// Creates a response; [status] must be within 100–599.
  HttpResponse(int status, {HeaderMap? headers, ResponseBody? body})
    : status = RangeError.checkValueInInterval(status, 100, 599, 'status'),
      headers = HeaderMap.unmodifiable(headers ?? HeaderMap()),
      body = body ?? BytesBody(const []);

  /// A `text/plain; charset=utf-8` response.
  factory HttpResponse.text(
    String text, {
    int status = StatusCode.ok,
    HeaderMap? headers,
  }) => _typed(
    status,
    headers,
    'text/plain; charset=utf-8',
    BytesBody(utf8.encode(text)),
  );

  /// An `application/json; charset=utf-8` response with [value] encoded by
  /// `jsonEncode` (so objects with `toJson()` work).
  factory HttpResponse.json(
    Object? value, {
    int status = StatusCode.ok,
    HeaderMap? headers,
  }) => _typed(
    status,
    headers,
    'application/json; charset=utf-8',
    BytesBody(utf8.encode(jsonEncode(value))),
  );

  /// An `application/octet-stream` response.
  factory HttpResponse.bytes(
    List<int> bytes, {
    int status = StatusCode.ok,
    HeaderMap? headers,
  }) => _typed(status, headers, 'application/octet-stream', BytesBody(bytes));

  /// A streamed response of [contentType].
  factory HttpResponse.stream(
    Stream<List<int>> stream, {
    int status = StatusCode.ok,
    HeaderMap? headers,
    String contentType = 'application/octet-stream',
  }) => _typed(status, headers, contentType, StreamBody(stream));

  /// A redirect to [location] (302 unless [status] says otherwise).
  factory HttpResponse.redirect(
    Uri location, {
    int status = StatusCode.found,
  }) => HttpResponse(
    status,
    headers: HeaderMap.of({'location': location.toString()}),
  );

  /// A response without a body (204 unless [status] says otherwise).
  factory HttpResponse.empty({
    int status = StatusCode.noContent,
    HeaderMap? headers,
  }) => HttpResponse(status, headers: headers);

  /// Status code.
  final int status;

  /// Read-only headers.
  final HeaderMap headers;

  /// The body.
  final ResponseBody body;

  /// A copy that also carries every header of [extra] whose name this
  /// response does not set; the response's own values win.
  HttpResponse mergeHeaders(HeaderMap extra) {
    final missing = [
      for (final name in extra.names)
        if (!headers.contains(name)) name,
    ];
    if (missing.isEmpty) return this;
    final merged = HeaderMap.copy(headers);
    for (final name in missing) {
      for (final value in extra.all(name)) {
        merged.add(name, value);
      }
    }
    return HttpResponse(status, headers: merged, body: body);
  }

  static HttpResponse _typed(
    int status,
    HeaderMap? headers,
    String contentType,
    ResponseBody body,
  ) {
    final all = HeaderMap.copy(headers ?? HeaderMap());
    if (!all.contains('content-type')) all.set('content-type', contentType);
    return HttpResponse(status, headers: all, body: body);
  }

  @override
  String toString() => 'HttpResponse($status)';
}
