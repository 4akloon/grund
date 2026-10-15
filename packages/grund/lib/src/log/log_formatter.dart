import 'package:logging/logging.dart';

/// Turns a [LogRecord] into the text of one log entry.
abstract interface class LogFormatter {
  /// The entry for [record], without a trailing newline.
  String format(LogRecord record);
}
