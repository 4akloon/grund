import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

LogRecord record({Object? error, StackTrace? stackTrace}) => LogRecord(
  Level.INFO,
  'AuthModule initialized +2ms',
  'grund.modules',
  error,
  stackTrace,
);

void main() {
  group('ConsoleLogFormatter', () {
    test('writes time, level, logger and message on one line', () {
      final line = const ConsoleLogFormatter().format(record());

      expect(
        line,
        matches(
          r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}  INFO  '
          r'\[grund\.modules\] AuthModule initialized \+2ms$',
        ),
      );
    });

    test('appends the error and the stack trace on following lines', () {
      final line = const ConsoleLogFormatter().format(
        record(error: StateError('boom'), stackTrace: StackTrace.current),
      );

      final lines = line.split('\n');
      expect(lines[1], contains('boom'));
      expect(lines.length, greaterThan(2));
    });

    test('colors only the level when asked', () {
      final logRecord = record();
      final plain = const ConsoleLogFormatter().format(logRecord);
      final colored = const ConsoleLogFormatter(color: true).format(logRecord);

      expect(plain, isNot(contains('\x1B')));
      expect(colored, contains('\x1B[32mINFO\x1B[0m'));
      expect(colored.replaceAll(RegExp('\x1B\\[[0-9;]*m'), ''), plain);
    });
  });

  group('JsonLogFormatter', () {
    test('writes one object with the record fields', () {
      final decoded =
          jsonDecode(const JsonLogFormatter().format(record()))
              as Map<String, Object?>;

      expect(decoded.keys, ['time', 'level', 'logger', 'message']);
      expect(decoded['level'], 'INFO');
      expect(decoded['logger'], 'grund.modules');
      expect(decoded['message'], 'AuthModule initialized +2ms');
      expect(decoded['time'], endsWith('Z'));
    });

    test('adds error and stack when present', () {
      final decoded =
          jsonDecode(
                const JsonLogFormatter().format(
                  record(
                    error: StateError('boom'),
                    stackTrace: StackTrace.empty,
                  ),
                ),
              )
              as Map<String, Object?>;

      expect(decoded['error'], contains('boom'));
      expect(decoded, contains('stack'));
    });
  });
}
