import 'package:grund_shelf/src/guarded_reporter.dart';
import 'package:test/test.dart';

import 'helpers/captured_stderr.dart';

void main() {
  group('GuardedReporter', () {
    test('hands the error and stack trace to onError', () {
      final received = <Object>[];
      final stackTrace = StackTrace.current;

      GuardedReporter((error, trace) => received.addAll([error, trace]))(
        StateError('boom'),
        stackTrace,
      );

      expect(received, [isA<StateError>(), same(stackTrace)]);
    });

    test(
      'writes a failure of onError with its stack trace to stderr',
      () async {
        final reporter = GuardedReporter(
          (_, _) => throw StateError('reporter failed'),
        );

        final written = await captureStderr(
          () async => reporter(StateError('boom'), StackTrace.current),
        );

        expect(written, contains('onError failed: Bad state: reporter failed'));
        expect(written, contains('guarded_reporter_test.dart'));
      },
    );
  });
}
