import 'package:grund/grund.dart';

import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/problem_code.dart';
import '../http/problem_responder.dart';
import '../routing/route_match.dart';
import 'route_executor.dart';
import 'route_table.dart';

/// Routes one request and serves it; always answers.
final class RequestDispatcher {
  /// Creates the dispatcher.
  const RequestDispatcher({required this.executor, required this.problems});

  /// Serves a matched route.
  final RouteExecutor executor;

  /// Answers the requests that match no route.
  final ProblemResponder problems;

  /// Answers [request] with [table]: 400 for a malformed percent-encoding in
  /// the path, 404 for an unknown path, 405 with `allow` for a known path
  /// with another method, otherwise the route's response. Path segments are
  /// percent-decoded and empty segments are ignored, so `/users/` and
  /// `/users//1` match `/users` and `/users/1`.
  Future<HttpResponse> dispatch(
    HttpRequest request,
    RouteTable table,
    CancelSignal cancel,
  ) async {
    final segments = _segments(request);
    if (segments == null) {
      return _problem(
        request,
        const BadRequestException(
          message: 'Malformed percent-encoding in path',
          code: ProblemCode.parameterInvalid,
        ),
      );
    }
    return switch (table.match(request.method, segments)) {
      RouteFound(:final value, :final parameters) => executor.execute(
        request,
        value,
        parameters,
        cancel,
      ),
      RouteMethodNotAllowed(:final allowed) => _problem(
        request,
        MethodNotAllowedException(allowed, code: ProblemCode.methodNotAllowed),
      ),
      RouteNotFound() => _problem(
        request,
        NotFoundException(
          message: 'Cannot ${request.method} ${request.uri.path}',
          code: ProblemCode.routeNotFound,
        ),
      ),
    };
  }

  HttpResponse _problem(HttpRequest request, HttpException error) =>
      problems.respond(error, StackTrace.current, instance: request.uri.path);

  /// The decoded non-empty path segments, or null when the path holds an
  /// invalid percent-encoded UTF-8 sequence (`Uri.pathSegments` throws).
  static List<String>? _segments(HttpRequest request) {
    try {
      return [
        for (final segment in request.uri.pathSegments)
          if (segment.isNotEmpty) segment,
      ];
    } on FormatException {
      return null;
    }
  }
}
