import '../http/http_request.dart';
import '../http/http_response.dart';
import 'middleware.dart';

/// Runs a list of [Middleware] around a terminal handler.
abstract final class MiddlewareChain {
  /// Calls the first of [middleware] with a `next` that calls the second and
  /// so on; the last `next` calls [terminal].
  static Future<HttpResponse> run(
    List<Middleware> middleware,
    HttpRequest request,
    Future<HttpResponse> Function() terminal,
  ) => _step(middleware, 0, request, terminal);

  static Future<HttpResponse> _step(
    List<Middleware> middleware,
    int index,
    HttpRequest request,
    Future<HttpResponse> Function() terminal,
  ) {
    if (index == middleware.length) return terminal();
    return middleware[index].handle(
      request,
      () => _step(middleware, index + 1, request, terminal),
    );
  }
}
