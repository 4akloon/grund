import 'package:grund_http/grund_http.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'shelf_request_mapper.dart';
import 'shelf_response_mapper.dart';

/// A shelf handler that answers through a grund [RequestHandler].
final class ShelfBridge {
  /// Bridges to [handler]; [onError] receives a failure of [handler] or of
  /// discarding a `HEAD` body and must not throw.
  ShelfBridge(this.handler, {required this.onError});

  /// Answers the mapped requests (usually the `HttpServer` request handler).
  final RequestHandler handler;

  /// Where a failure of [handler] is reported.
  final ErrorLogger onError;

  /// Answers [request]; never throws.
  Future<shelf.Response> call(shelf.Request request) async {
    final response = await _answer(request);
    final isHead = request.method == 'HEAD';
    if (isHead) await _discardBody(response.body);
    return ShelfResponseMapper.map(response, isHead: isHead);
  }

  Future<HttpResponse> _answer(shelf.Request request) async {
    // Request boundary: the HttpServer request handler only fails
    // when the application's own error logger throws; answer 500 without a body.
    try {
      return await handler(ShelfRequestMapper.map(request));
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }

  Future<void> _discardBody(ResponseBody body) async {
    if (body is! StreamBody) return;
    // Body boundary: cancelling the user's stream runs its onCancel, which
    // can throw (or the stream may already be listened to); the HEAD head
    // is unaffected, so report the failure and answer.
    try {
      await body.stream.listen(null).cancel();
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }
}
