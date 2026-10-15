import '../http/http_request.dart';
import '../http/http_response.dart';

/// Continues with the next middleware, or the routing when there is none.
typedef Next = Future<HttpResponse> Function();

/// Code around the whole request, before routing: CORS, compression, request
/// ids, rate limits.
///
/// A middleware either answers itself or returns what `next()` produced,
/// possibly changed. It sees every request, also those that match no route.
/// Unlike an `HttpHook` it knows nothing about the route or the call scope.
abstract interface class Middleware {
  /// Handles [request]; call [next] to continue.
  Future<HttpResponse> handle(HttpRequest request, Next next);
}
