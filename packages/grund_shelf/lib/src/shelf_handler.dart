import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'guarded_reporter.dart';
import 'shelf_adapter.dart';
import 'shelf_bridge.dart';

/// A shelf [shelf.Handler] that answers through the `HttpServer` of [app],
/// for embedding a grund application in an existing shelf pipeline.
///
/// Start [app] with `only: const {}`: the graph is built and the routes are
/// prepared, but the application opens no port of its own; the user's shelf
/// server does. The root module of [app] must import `HttpModule` and
/// an adapter module (`ShelfAdapterModule`), because the server depends on
/// `HttpAdapter`. Asking for the handler of an application
/// that is not started throws `ApplicationStateError`; a request after
/// `app.close()` is answered with 503.
///
/// The pipeline stays the user's: the handler changes nothing around it.
/// The application sees paths relative to the shelf `handlerPath`, so it
/// can be mounted under a prefix. [app] is not closed with the server.
/// [onError] receives a failure of the request handler (only possible when
/// the application's own `ErrorLog` throws), answered with a 500 without a
/// body; it defaults to [ShelfAdapter.printError]. A failure of [onError]
/// itself goes to stderr.
///
/// Routing uses the path shelf hands over (`Request.url`). A plain
/// `shelf_io` server derives it from `Host` and the client-controlled
/// `X-Forwarded-Host`; behind it, strip or overwrite those headers. Use
/// `ShelfAdapterModule` to be independent of them.
///
/// ```dart
/// final app = App(root: AppModule());
/// await app.start(only: const {});
/// final handler = const shelf.Pipeline()
///     .addMiddleware(shelf.logRequests())
///     .addHandler(shelfHandler(app));
/// await shelf_io.serve(handler, 'localhost', 8080);
/// ```
shelf.Handler shelfHandler(App app, {ErrorLogger? onError}) {
  final server = app.container.root<HttpServer>();
  return ShelfBridge(
    (request) async => app.isRunning
        ? server.handle(request)
        : HttpResponse(StatusCode.serviceUnavailable),
    onError: GuardedReporter(onError ?? ShelfAdapter.printError).call,
  ).call;
}
