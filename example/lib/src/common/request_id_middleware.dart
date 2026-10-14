import 'package:dartnest/dartnest.dart';

/// HTTP middleware: answers every request, routed or not, with an
/// `x-request-id` header, the caller's own or `req-<n>`.
final class RequestIdMiddleware {
  int _count = 0;

  /// Runs [next] and adds the id to its response; pass the tear-off to
  /// `Application.use`.
  Future<HttpResponse> call(
    HttpRequest request,
    Next<HttpResponse> next,
  ) async {
    final id = request.headers['x-request-id'] ?? 'req-${++_count}';
    final response = await next();
    return response.mergeHeaders(HeaderMap.of({'x-request-id': id}));
  }
}
