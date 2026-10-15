import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';

/// A module without bindings: the smallest graph that has a call scope.
final class EmptyModule extends Module {
  const EmptyModule();
}

/// Builds [HttpCtx]s over real call scopes of an empty application.
final class CtxFactory {
  CtxFactory._(this._app);

  final TestApp _app;

  /// Starts the empty application.
  static Future<CtxFactory> start() async =>
      CtxFactory._(await TestApp.start(root: const EmptyModule()));

  /// A context for [request].
  HttpCtx call(
    HttpRequest request, {
    Map<String, String> pathParameters = const {},
    int? maxBodyBytes,
    CancelSignal? cancel,
  }) => HttpCtx(
    request: request,
    scope: _app.injector.openCall(),
    response: ResponseHead(),
    pathParameters: pathParameters,
    maxBodyBytes: maxBodyBytes,
    cancel: cancel,
  );

  /// Closes the application.
  Future<void> close() => _app.close();
}
