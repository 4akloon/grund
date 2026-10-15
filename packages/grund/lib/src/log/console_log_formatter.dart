import 'package:logging/logging.dart';

import 'log_formatter.dart';

/// Formats a record as one human-readable line:
/// `2026-10-15 10:00:00.123  INFO  [grund.modules] AuthModule initialized +2ms`.
///
/// An error and a stack trace follow on their own lines. With [color] the
/// level name is wrapped in ANSI escapes. The result depends only on the
/// record.
final class ConsoleLogFormatter implements LogFormatter {
  /// Creates the formatter.
  const ConsoleLogFormatter({this.color = false});

  /// Whether the level name is colored with ANSI escapes.
  final bool color;

  @override
  String format(LogRecord record) {
    final buffer = StringBuffer()
      ..write(_time(record.time))
      ..write('  ')
      ..write(_level(record.level))
      ..write('  [')
      ..write(record.loggerName)
      ..write('] ')
      ..write(record.message);
    final error = record.error;
    if (error != null) buffer.write('\n$error');
    final stackTrace = record.stackTrace;
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }

  String _level(Level level) {
    final name = level.name.padRight(4);
    if (!color) return name;
    return '\x1B[${_colorCode(level)}m$name\x1B[0m';
  }

  static int _colorCode(Level level) {
    if (level >= Level.SEVERE) return 31;
    if (level >= Level.WARNING) return 33;
    if (level >= Level.INFO) return 32;
    return 90;
  }

  static String _time(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final millis = time.millisecond.toString().padLeft(3, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
  }
}
