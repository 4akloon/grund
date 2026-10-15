import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Records the log records of the loggers whose name starts with `grund`.
///
/// Raises the root level to [Level.ALL] and puts it back in a tear-down.
final class LogCapture {
  LogCapture._();

  /// Starts recording; the tear-down of the current test undoes it.
  factory LogCapture.start() {
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    late final LogCapture capture;
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.loggerName.startsWith('grund')) capture.records.add(record);
    });
    capture = LogCapture._();
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previous;
    });
    return capture;
  }

  /// What was recorded, oldest first.
  final List<LogRecord> records = [];

  /// The messages of [loggerName], after letting pending records arrive.
  Future<List<String>> messages(String loggerName) async {
    await Future<void>.delayed(Duration.zero);
    return [
      for (final record in records)
        if (record.loggerName == loggerName) record.message,
    ];
  }
}
