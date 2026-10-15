import 'package:logging/logging.dart';

import 'reassemble_report.dart';

/// The lifecycle messages of an `App`, logged on `grund.app`.
///
/// The stable texts are constants so that tests and docs name them once.
final class AppLog {
  /// Creates the log; its clock starts now and times `started`.
  AppLog() : _clock = Stopwatch()..start();

  /// The logger name.
  static const loggerName = 'grund.app';

  /// Logged before the container is built.
  static const startingMessage = 'Starting application';

  /// Logged when the runners started, followed by the elapsed time.
  static const startedMessage = 'Application started';

  /// Logged when `close` begins.
  static const shuttingDownMessage = 'Shutting down';

  /// Logged when `close` ended.
  static const closedMessage = 'Application closed';

  /// Logged when a failed start is undone, followed by the error.
  static const rollbackMessage = 'Startup failed, rolling back: ';

  /// Logged when a reassemble fails, followed by the error.
  static const reassembleFailedMessage = 'Reassemble failed: ';

  static final Logger _logger = Logger(loggerName);

  final Stopwatch _clock;

  /// Announces the start.
  void starting() => _logger.info(startingMessage);

  /// Reports how many singletons the container holds.
  void singletonsCreated(int count) => _logger.info(
    count == 1 ? '1 singleton created' : '$count singletons created',
  );

  /// Reports the start, with the time since this log was created.
  void started() =>
      _logger.info('$startedMessage +${_clock.elapsedMilliseconds}ms');

  /// Announces the shutdown.
  void shuttingDown() => _logger.info(shuttingDownMessage);

  /// Reports the end of the shutdown.
  void closed() => _logger.info(closedMessage);

  /// Warns that a failed start is rolled back because of [error].
  void rollingBack(Object error) => _logger.warning('$rollbackMessage$error');

  /// Reports what a reassemble changed.
  void reassembled(ReassembleReport report) => _logger.info(
    'Reassembled: +${report.added.length} added, '
    '-${report.removed.length} removed',
  );

  /// Warns that a reassemble failed with [error].
  void reassembleFailed(Object error) =>
      _logger.warning('$reassembleFailedMessage$error');
}
