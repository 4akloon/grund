import 'dart:io' as io;

import 'package:grund_http/grund_http.dart';

/// Hands failures to a user-supplied [ErrorLogger] without letting the
/// logger's own failure escape. Not exported: `ShelfAdapter` and
/// `shelfHandler` share it.
final class GuardedReporter {
  /// Guards [onError].
  GuardedReporter(this.onError);

  /// The user's logger.
  final ErrorLogger onError;

  /// Reports [error] to [onError]; a failure of [onError] goes to stderr.
  void call(Object error, StackTrace stackTrace) {
    // Reporter boundary: onError is user code; a failing reporter must not
    // stop the 500 or crash the server, so its failure goes to stderr.
    try {
      onError(error, stackTrace);
    } on Object catch (reporterError, reporterStackTrace) {
      io.stderr.writeln(
        'grund_shelf: onError failed: $reporterError\n$reporterStackTrace',
      );
    }
  }
}
