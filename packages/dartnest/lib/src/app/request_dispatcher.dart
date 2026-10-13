import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/response_head.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/execution_context.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/pipeline.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/transport.dart';
import '../routing/route_match.dart';
import '../routing/router.dart';

/// Routes one request and runs it through the pipeline; always answers.
final class RequestDispatcher {
  /// Creates the dispatcher.
  const RequestDispatcher({required this.serializer, required this.errors});

  /// Turns results into responses.
  final ResponseSerializer serializer;

  /// The default exception filter.
  final HttpErrorResponder errors;

  /// Answers [request] with [router]: 404 for an unknown path, 405 with
  /// `allow` for a known path with another method, otherwise the pipeline's
  /// response. Path segments are percent-decoded and empty segments are
  /// ignored, so `/users/` and `/users//1` match `/users` and `/users/1`.
  Future<HttpResponse> dispatch(
    HttpRequest request,
    Router<Endpoint> router,
  ) async {
    final segments = [
      for (final segment in request.uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    return switch (router.match(request.method, segments)) {
      RouteFound(:final value, :final parameters) => _run(
        request,
        value,
        parameters,
      ),
      RouteMethodNotAllowed(:final allowed) => errors.respond(
        MethodNotAllowedException(allowed),
        StackTrace.current,
      ),
      RouteNotFound() => errors.respond(
        NotFoundException(
          message: 'Cannot ${request.method} ${request.uri.path}',
        ),
        StackTrace.current,
      ),
    };
  }

  Future<HttpResponse> _run(
    HttpRequest request,
    Endpoint endpoint,
    Map<String, String> parameters,
  ) async {
    final head = ResponseHead();
    final context = ExecutionContext(
      transport: HttpContext(
        request: request,
        response: head,
        pathParameters: parameters,
      ),
      controllerType: endpoint.controllerType,
      handlerName: endpoint.handlerName,
      metadata: endpoint.metadata,
      pipes: endpoint.enhancers.pipes,
    );
    // Request boundary: errors no filter handled become the default
    // filter's response; head headers (for example www-authenticate set by
    // a guard) are kept.
    try {
      return await Pipeline.run(
        endpoint,
        context,
        (result) => serializer.serialize(result, head),
      );
    } on Object catch (error, stackTrace) {
      return errors.respond(error, stackTrace).mergeHeaders(head.headers);
    }
  }
}
