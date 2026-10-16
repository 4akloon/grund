import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

/// Turns what Jaspr rendered into an [HttpResponse].
///
/// Header names are lower-cased; every `set-cookie` value is kept, for any
/// other name the last spelling Jaspr holds wins (`Content-Type` is Jaspr's
/// default, `content-type` a component's own). `content-length` is dropped:
/// the adapter sets it for the body it sends. A missing `content-type`, or
/// `text/html` without a charset, becomes `text/html; charset=utf-8` (Jaspr
/// writes UTF-8); a page without `cache-control` gets `private, no-cache`,
/// since it may depend on the session.
abstract final class JasprResponse {
  /// The `content-type` of a rendered page.
  static const htmlType = 'text/html; charset=utf-8';

  /// The response for [rendered].
  static HttpResponse from(ResponseLike rendered) => HttpResponse(
    rendered.statusCode,
    headers: _headers(rendered.headers),
    body: BytesBody(rendered.body),
  );

  /// Whether [contentType] is `text/html`, with or without parameters.
  static bool isHtml(String contentType) =>
      contentType.split(';').first.trim().toLowerCase() == 'text/html';

  static HeaderMap _headers(Map<String, List<String>> rendered) {
    final headers = HeaderMap();
    for (final MapEntry(:key, :value) in rendered.entries) {
      final name = key.toLowerCase();
      if (name == 'content-length') continue;
      if (name != 'set-cookie') headers.remove(name);
      for (final item in value) {
        headers.add(name, item);
      }
    }
    final type = headers['content-type'];
    if (type == null ||
        (isHtml(type) && !type.toLowerCase().contains('charset='))) {
      headers.set('content-type', htmlType);
    }
    if (!headers.contains('cache-control')) {
      headers.set('cache-control', 'private, no-cache');
    }
    return headers;
  }
}
