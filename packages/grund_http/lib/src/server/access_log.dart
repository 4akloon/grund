import 'package:logging/logging.dart';

import '../http/http_request.dart';
import '../http/http_response.dart';

/// Logs one `INFO` line per answered request on `grund.access`:
/// `GET /tasks/1 200 12ms` (method, path without the query, status, time).
final class AccessLog {
  /// Creates the access log; with [enabled] false it does nothing, not even
  /// start a clock.
  AccessLog({required this.enabled});

  /// Whether requests are logged.
  final bool enabled;

  static final Logger _logger = Logger('grund.access');

  /// Runs [serve] and logs its response. A failure of [serve] logs nothing
  /// and goes on to the caller.
  Future<HttpResponse> record(
    HttpRequest request,
    Future<HttpResponse> Function() serve,
  ) async {
    if (!enabled) return serve();
    final clock = Stopwatch()..start();
    final response = await serve();
    _logger.info(
      '${request.method} ${request.uri.path} ${response.status} '
      '${clock.elapsedMilliseconds}ms',
    );
    return response;
  }
}
