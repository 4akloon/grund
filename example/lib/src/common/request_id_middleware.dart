import 'package:grund_http/grund_http.dart';

/// Answers every request, routed or not, with an `x-request-id` header:
/// the caller's own or `req-<n>`.
final class RequestIdMiddleware implements Middleware {
  int _count = 0;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    final id = request.headers['x-request-id'] ?? 'req-${++_count}';
    final response = await next();
    return response.mergeHeaders(HeaderMap.of({'x-request-id': id}));
  }
}
