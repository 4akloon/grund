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
    final alone = html.replaceFirst(_script(clientId), '');
    if (alone == html) return response;
    // The removed `<head>` leaves the line break that followed it.
    return HttpResponse(
      response.status,
      headers: response.headers,
      body: BytesBody(utf8.encode(alone.trimLeft())),
    );
  }

  /// [response] without the `clientId` script unless its page holds a client
  /// component (an island marker); anything else is as it is: no `clientId`,
  /// a body that is not bytes, or a marker in the body.
  ///
  /// Only the script tag goes; a `<head>` it leaves empty goes with it.
  static HttpResponse unlessIslands(HttpResponse response) {
    final clientId = Jaspr.options.clientId;
    final body = response.body;
    if (clientId == null || body is! BytesBody) return response;
    final html = utf8.decode(body.bytes);
    if (_island.hasMatch(html)) return response;
    final alone = html.replaceFirst(_script(clientId), '');
    final cleaned = alone == html
        ? html.replaceFirst(_tag(clientId), '')
        : alone;
    if (cleaned == html) return response;
    return HttpResponse(
      response.status,
      headers: response.headers,
      body: BytesBody(utf8.encode(cleaned)),
    );
  }

  /// An island marker: `<!--@` and a component name, then a space or the end
  /// of the comment.
  static final RegExp _island = RegExp(r'<!--@[a-z0-9_-]+(?: |-->)');

  /// The script tag alone. Jaspr writes the src with or without a leading
  /// slash (relative to a base).
  static String _tagSource(String clientId) =>
      r'<script\s+src="/?'
      '${RegExp.escape(clientId)}'
      r'"\s+defer\s*(?:=\s*"")?\s*>\s*</script>';

  static RegExp _tag(String clientId) => RegExp(_tagSource(clientId));

  /// The `<head>` that holds the `clientId` script and nothing else. Jaspr
  /// writes the src with or without a leading slash (relative to a base).
  static RegExp _script(String clientId) =>
      RegExp('<head>\\s*${_tagSource(clientId)}\\s*</head>');
}
