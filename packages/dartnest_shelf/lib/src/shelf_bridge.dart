import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'shelf_request_mapper.dart';
import 'shelf_response_mapper.dart';

/// A shelf handler that answers through a dartnest [RequestHandler].
final class ShelfBridge {
  /// Bridges to [handler]; [onError] receives a failure of [handler] and
  /// must not throw.
  ShelfBridge(this.handler, {required this.onError});

  /// Answers the mapped requests (usually `Application.handle`).
  final RequestHandler handler;

  /// Where a failure of [handler] is reported.
  final ErrorLogger onError;

  /// Answers [request]; never throws.
  Future<shelf.Response> call(shelf.Request request) async =>
      ShelfResponseMapper.map(
        await _answer(request),
        isHead: request.method == 'HEAD',
      );

  Future<HttpResponse> _answer(shelf.Request request) async {
    // Request boundary: Application.handle only fails when the
    // application's own error logger throws; answer 500 without a body.
    try {
      return await handler(ShelfRequestMapper.map(request));
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }
}
