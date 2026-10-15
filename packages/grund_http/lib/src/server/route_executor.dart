import 'package:grund/grund.dart';

import '../ctx/http_ctx.dart';
import '../hook/hook_chain.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/problem_responder.dart';
import '../http/response_head.dart';
import '../serialize/response_serializer.dart';
import 'route_entry.dart';

/// Runs one matched route for one request: opens the call scope, runs the
/// hooks and the handler, serializes the result, closes the scope. Always
/// answers.
final class RouteExecutor {
  /// Creates the executor.
  const RouteExecutor({
    required this.serializer,
    required this.problems,
    this.maxBodyBytes,
  });

  /// Turns the handler result into a response.
  final ResponseSerializer serializer;

  /// Turns failures into problem responses and reports unexpected ones.
  final ProblemResponder problems;

  /// The request body limit; `null` for none.
  final int? maxBodyBytes;

  /// Serves [request] with [entry]; [cancel] fires when the server stops
  /// waiting for the request.
  Future<HttpResponse> execute(
    HttpRequest request,
    RouteEntry entry,
    Map<String, String> pathParameters,
    CancelSignal cancel,
  ) async {
    final head = ResponseHead();
    final c = HttpCtx(
      request: request,
      scope: entry.api.injector.openCall(),
      response: head,
      pathParameters: pathParameters,
      cancel: cancel,
      maxBodyBytes: maxBodyBytes,
    );
    // Request boundary: hooks, the handler and the serializer are user code;
    // whatever they throw (also when no hook answers) becomes a problem
    // response that keeps the headers set so far, such as www-authenticate.
    try {
      final chain = HookChain.resolve(entry.hooks, c.scope);
      final result = await chain.run(c, entry.route.handler);
      if (entry.route.status case final status?) head.status = status;
      return serializer.serialize(result, head);
    } on Object catch (error, stackTrace) {
      return problems
          .respond(error, stackTrace, instance: request.uri.path)
          .mergeHeaders(head.headers);
    } finally {
      await _close(c);
    }
  }

  Future<void> _close(HttpCtx c) async {
    try {
      await c.close();
    } on ShutdownError catch (error, stackTrace) {
      // Disposing the call's Scoped instances failed; the response is
      // already decided, so the failure is reported, not turned into one.
      problems.log.report(error, stackTrace);
    }
  }
}
