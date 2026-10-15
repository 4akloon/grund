import 'dart:typed_data';

import 'package:grund/grund.dart';

import '../http/http_request.dart';
import '../http/response_head.dart';
import 'body_reader.dart';
import 'cookie_header.dart';
import 'param_location.dart';
import 'params.dart';

/// The context of one HTTP request: the request, the response being built,
/// typed readers for its parameters and body, and (through [CallContext]) the
/// call scope that resolves `Scoped` bindings and values hooks [set].
///
/// A new context is created for every request and closed when the response
/// is complete; nothing on it is shared between requests.
final class HttpCtx extends CallContext {
  /// Creates the context for [request], routed with [pathParameters].
  ///
  /// [maxBodyBytes] limits the body readers (`null`: no limit).
  HttpCtx({
    required this.request,
    required CallScope scope,
    required this.response,
    required Map<String, String> pathParameters,
    CancelSignal? cancel,
    int? maxBodyBytes,
  }) : path = Params(
         ParamLocation.path,
         (name) => [if (pathParameters[name] case final value?) value],
       ),
       query = Params(
         ParamLocation.query,
         (name) => request.uri.queryParametersAll[name] ?? const [],
       ),
       headers = Params(ParamLocation.header, request.headers.all),
       cookies = _cookies(request),
       _body = BodyReader(request, maxBodyBytes),
       super(scope, cancel: cancel);

  /// The request being served.
  final HttpRequest request;

  /// The status and headers the response will get; the handler may change
  /// them (`c.response.status = 201`).
  final ResponseHead response;

  /// Readers for the `:name` segments of the route path.
  final Params path;

  /// Readers for the query string.
  final Params query;

  /// Readers for the request headers.
  final Params headers;

  /// Readers for the cookies of the request.
  final Params cookies;

  final BodyReader _body;

  /// The body as one JSON object built with [fromJson].
  ///
  /// A body that is not UTF-8, not JSON, not an object, or that [fromJson]
  /// rejects (a `FormatException`, or a missing or mistyped field) is a 400
  /// with the code `body_invalid` and the pointer `/body`; a body over the
  /// limit is a 413 with the code `body_too_large`.
  Future<T> body<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) => _body.object(fromJson);

  /// The body as a JSON array of objects, each built with [fromJson]; errors
  /// as in [body], with the pointer `/body/<index>` for a bad item.
  Future<List<T>> bodyList<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) => _body.list(fromJson);

  /// The raw body; a body over the limit is a 413.
  Future<Uint8List> bytes() => _body.bytes();

  static Params _cookies(HttpRequest request) {
    final cookies = CookieHeader.parse(request.headers.all('cookie'));
    return Params(ParamLocation.cookie, (name) => cookies[name] ?? const []);
  }
}
