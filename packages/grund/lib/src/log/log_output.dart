import 'dart:io';

import 'package:logging/logging.dart';

import 'console_log_formatter.dart';
import 'json_log_formatter.dart';
import 'log_formatter.dart';
import 'log_subscription.dart';

/// Where the log records of `Logger.root` go: a formatter and a sink.
///
/// The framework never configures `Logger.root` itself; `App.run` attaches
/// the output you give it, and anything else calls [attach] (or listens to
/// `Logger.root.onRecord` directly).
final class LogOutput {
  /// Human-readable lines. [color] defaults to whether stdout understands
  /// ANSI escapes; [sink] defaults to stdout, and stderr from `WARNING` up.
  const LogOutput.console({this.level = Level.INFO, this.color, this.sink})
    : _json = false,
      _enabled = true;

  /// One JSON object per line, see [JsonLogFormatter].
  const LogOutput.json({this.level = Level.INFO, this.sink})
    : color = null,
      _json = true,
      _enabled = true;

  /// Attaches nothing: for an application that configures `Logger.root`
  /// itself.
  const LogOutput.none()
    : level = Level.INFO,
      color = null,
      sink = null,
      _json = false,
      _enabled = false;

  /// The level `Logger.root` gets while attached.
  final Level level;

  /// Whether the console output is colored; `null` asks stdout.
  final bool? color;

  /// Receives each formatted line; `null` writes to stdout/stderr.
  final void Function(String line)? sink;

  final bool _json;
  final bool _enabled;

  /// Sets `Logger.root.level` to [level] and writes every record to the sink
  /// until the returned subscription is cancelled.
  LogSubscription attach() {
    if (!_enabled) return LogSubscription.empty();
    final formatter = _formatter();
    final previous = Logger.root.level;
    Logger.root.level = level;
    final subscription = Logger.root.onRecord.listen((record) {
      _write(record, formatter.format(record));
    });
    return LogSubscription.of(subscription, previous);
  }

  LogFormatter _formatter() => _json
      ? const JsonLogFormatter()
      : ConsoleLogFormatter(color: color ?? stdout.supportsAnsiEscapes);

  void _write(LogRecord record, String line) {
    final target = sink;
    if (target != null) return target(line);
    (record.level >= Level.WARNING ? stderr : stdout).writeln(line);
  }
}
