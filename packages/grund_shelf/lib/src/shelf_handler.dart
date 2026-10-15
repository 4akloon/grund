import 'package:grund/grund.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'guarded_reporter.dart';
import 'shelf_adapter.dart';
import 'shelf_bridge.dart';

/// A shelf [shelf.Handler] that answers through [app], for embedding a
/// grund application in an existing shelf pipeline.
///
/// The pipeline stays the user's: the handler changes nothing around it.
/// The application sees paths relative to the shelf `handlerPath`, so it
/// can be mounted under a prefix. [app] is not closed with the server;
/// after `app.close()` the handler answers 503. [onError] receives a
/// failure of `app.handle` (only possible when the application's own error
/// logger throws), answered with a 500 without a body; it defaults to
/// [ShelfAdapter.printError]. A failure of [onError] itself goes to stderr.
///
/// Routing uses the path shelf hands over (`Request.url`). A plain
/// `shelf_io` server derives it from `Host` and the client-controlled
/// `X-Forwarded-Host`; behind it, strip or overwrite those headers. Use
/// `ShelfAdapter` to be independent of them.
///
/// ```dart
/// final handler = const shelf.Pipeline()
///     .addMiddleware(shelf.logRequests())
///     .addHandler(shelfHandler(app));
/// await shelf_io.serve(handler, 'localhost', 8080);
/// ```
shelf.Handler shelfHandler(Application app, {ErrorLogger? onError}) =>
    ShelfBridge(
      app.handle,
      onError: GuardedReporter(onError ?? ShelfAdapter.printError).call,
    ).call;
