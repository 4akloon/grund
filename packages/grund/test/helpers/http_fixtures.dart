// Shared builders for pipeline and HTTP tests.
import 'dart:convert';

import 'package:grund/grund.dart';

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

/// An HTTP context for [request] with the given matched path parameters.
ExecutionContext contextFor(
  HttpRequest request, {
  Map<String, String> pathParameters = const {},
  List<Object> metadata = const [],
}) => ExecutionContext(
  transport: HttpContext(
    request: request,
    response: ResponseHead(),
    pathParameters: pathParameters,
  ),
  controllerType: Object,
  handlerName: 'test',
  metadata: metadata,
);

/// The JSON value in the body of [response].
Future<Object?> jsonOf(HttpResponse response) async =>
    jsonDecode(utf8.decode(await response.body.readAll()));
