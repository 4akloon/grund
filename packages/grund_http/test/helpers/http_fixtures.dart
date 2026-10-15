// Shared builders for HTTP tests.
import 'dart:convert';

import 'package:grund_http/grund_http.dart';

/// A request for [method] and [target] with an optional JSON or raw body.
HttpRequest requestFor(
  String method,
  String target, {
  Map<String, String> headers = const {},
  String? body,
}) => HttpRequest(
  method: method,
  uri: Uri.parse(target),
  headers: HeaderMap.of(headers),
  body: body == null ? null : RequestBody.bytes(utf8.encode(body)),
);

/// The JSON value in the body of [response].
Future<Object?> jsonOf(HttpResponse response) async =>
    jsonDecode(utf8.decode(await response.body.readAll()));
