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

  /// A copy that also carries the headers of [extra]. A name this response
  /// does not set is added with all its values. Three names are combined
  /// instead of left to the response:
  ///
  /// - `set-cookie` and `link`: the values of [extra] come first, then the
  ///   response's own; both reach the client, and the response's own cookie
  ///   wins where both set the same one;
  /// - `vary`: the response's own tokens, then the tokens of [extra] it does
  ///   not name yet (case-insensitively), as a single line; `*` on either
  ///   side gives a single `vary: *`.
  ///
  /// For any other name the response's own values win.
  HttpResponse mergeHeaders(HeaderMap extra) {
    final added = [
      for (final name in extra.names)
        if (!headers.contains(name) || _combined.contains(name)) name,
    ];
    if (added.isEmpty) return this;
    final merged = HeaderMap.copy(headers);
    for (final name in added) {
      final own = merged.all(name);
      merged.remove(name);
      final values = name == _vary
          ? [_mergedVary(own, extra.all(name))]
          : [...extra.all(name), ...own];
      for (final value in values) {
        merged.add(name, value);
      }
    }
    return HttpResponse(status, headers: merged, body: body);
  }

  /// A copy whose `vary` names [header] (compared case-insensitively), as a
  /// single line with the existing tokens first. The same response when
  /// [header] is already named or `vary` is `*`.
  HttpResponse withVary(String header) {
    final tokens = _varyTokens(headers.all(_vary));
    if (tokens.contains('*') || tokens.contains(header.toLowerCase())) {
      return this;
    }
    final merged = HeaderMap.copy(headers)
      ..set(_vary, _mergedVary(headers.all(_vary), [header]));
    return HttpResponse(status, headers: merged, body: body);
  }

  static const _setCookie = 'set-cookie';
  static const _link = 'link';
  static const _vary = 'vary';
  static const _combined = {_setCookie, _link, _vary};

  static List<String> _varyTokens(List<String> values) => [
    for (final value in values)
      for (final token in value.split(','))
        if (token.trim().isNotEmpty) token.trim().toLowerCase(),
  ];

  /// One `vary` line: [own] tokens, then those of [added] not yet named, in
  /// the spelling they were written; `*` when either side holds it.
  static String _mergedVary(List<String> own, List<String> added) {
    final seen = <String>{};
    final tokens = <String>[];
    for (final value in [...own, ...added]) {
      for (final token in value.split(',').map((t) => t.trim())) {
        if (token.isNotEmpty && seen.add(token.toLowerCase()))
          tokens.add(token);
      }
    }
    return seen.contains('*') ? '*' : tokens.join(', ');
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
