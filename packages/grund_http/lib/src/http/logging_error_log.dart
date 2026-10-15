import 'package:logging/logging.dart';

import 'error_log.dart';

/// The default [ErrorLog]: logs the error and its stack trace as `SEVERE` on
/// the logger `grund.http`.
final class LoggingErrorLog implements ErrorLog {
  /// Creates the log.
  const LoggingErrorLog();

  static final Logger _logger = Logger('grund.http');

  @override
  void report(Object error, StackTrace stackTrace) =>
      _logger.severe('Unhandled error', error, stackTrace);
}
