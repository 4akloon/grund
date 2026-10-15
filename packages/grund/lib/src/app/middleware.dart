import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/interceptor.dart';

/// Application-level HTTP middleware: runs before routing, for every
/// request, in the order of `Application.use`; the first registered is the
/// outermost.
///
/// ```dart
/// app.use((request, next) async {
///   final response = await next();
///   return response.mergeHeaders(HeaderMap.of({'x-powered-by': 'grund'}));
/// });
/// ```
typedef Middleware =
    Future<HttpResponse> Function(HttpRequest request, Next<HttpResponse> next);
