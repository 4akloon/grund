import 'dart:convert';

import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

/// Removes the script of the application's client bundle from a rendered
/// fragment.
///
/// Jaspr adds that script to a standalone render as a `<head>` holding only
/// the script, which a fragment inserted into a page must not carry.
abstract final class ClientScriptRemoval {
  /// [response] without the `clientId` script, or as it is when it has none
  /// (no `clientId`, or a body that is not bytes).
  static HttpResponse from(HttpResponse response) {
    final clientId = Jaspr.options.clientId;
    final body = response.body;
    if (clientId == null || body is! BytesBody) return response;
    final html = utf8.decode(body.bytes);
    final cleaned = html.replaceFirst(_script(clientId), '');
    if (cleaned == html) return response;
    return HttpResponse(
      response.status,
      headers: response.headers,
      body: BytesBody(utf8.encode(cleaned)),
    );
  }

  /// The `<head>` that holds the `clientId` script and nothing else. Jaspr
  /// writes the src with or without a leading slash (relative to a base).
  static RegExp _script(String clientId) => RegExp(
    r'<head>\s*<script\s+src="/?'
    '${RegExp.escape(clientId)}'
    r'"\s+defer\s*(?:=\s*"")?\s*>\s*</script>\s*</head>',
  );
}
