import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'shelf_adapter.dart';
import 'shelf_bridge.dart';

/// A shelf [shelf.Handler] that answers through [app], for embedding a
/// dartnest application in an existing shelf pipeline.
///
/// The pipeline stays the user's: the handler changes nothing around it.
/// The application sees paths relative to the shelf `handlerPath`, so it
/// can be mounted under a prefix. [app] is not closed with the server;
/// after `app.close()` the handler answers 503. [onError] receives a
/// failure of `app.handle` (only possible when the application's own error
/// logger throws), answered with a 500 without a body; it defaults to
/// [ShelfAdapter.printError]. A failure of [onError] itself goes to stderr.
///
/// ```dart
/// final handler = const shelf.Pipeline()
///     .addMiddleware(shelf.logRequests())
///     .addHandler(shelfHandler(app));
/// await shelf_io.serve(handler, 'localhost', 8080);
/// ```
shelf.Handler shelfHandler(Application app, {ErrorLogger? onError}) {
  final report = onError ?? ShelfAdapter.printError;
  return ShelfBridge(
    app.handle,
    onError: (error, stackTrace) {
      // Reporter boundary: onError is user code; a failing reporter must not
      // stop the 500, so its failure goes to stderr.
      try {
        report(error, stackTrace);
      } on Object catch (reporterError) {
        io.stderr.writeln('dartnest_shelf: onError failed: $reporterError');
      }
    },
  ).call;
}
