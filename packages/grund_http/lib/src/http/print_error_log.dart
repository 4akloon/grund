import 'dart:io';

import 'error_log.dart';

/// The default [ErrorLog]: writes the error and its stack trace to stderr.
final class PrintErrorLog implements ErrorLog {
  /// Creates the log.
  const PrintErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) {
    stderr.writeln('grund: unhandled error: $error\n$stackTrace');
  }
}
