import 'dart:convert';

import 'package:logging/logging.dart';

import 'log_formatter.dart';

/// Formats a record as one JSON object per line with `time` (UTC, ISO-8601),
/// `level`, `logger` and `message`, plus `error` and `stack` when present.
final class JsonLogFormatter implements LogFormatter {
  /// Creates the formatter.
  const JsonLogFormatter();

  @override
  String format(LogRecord record) {
    final error = record.error;
    final stackTrace = record.stackTrace;
    return jsonEncode({
      'time': record.time.toUtc().toIso8601String(),
      'level': record.level.name,
      'logger': record.loggerName,
      'message': record.message,
      if (error != null) 'error': '$error',
      if (stackTrace != null) 'stack': '$stackTrace',
    });
  }
}
