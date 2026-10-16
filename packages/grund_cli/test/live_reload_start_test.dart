import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:grund_cli/src/dev/live_reload_start.dart';
import 'package:test/test.dart';

void main() {
  test('a bind failure becomes a software failure that says dev stopped', () {
    final start = LiveReloadStart.run(
      () => throw const SocketException('Address already in use'),
    );

    expect(
      start,
      throwsA(
        isA<CliFailure>()
            .having((f) => f.exitCode, 'exitCode', CliExitCode.software)
            .having(
              (f) => f.message,
              'message',
              allOf(startsWith('dev stopped:'), contains('already in use')),
            ),
      ),
    );
  });

  test('another failure is not turned into a CliFailure', () {
    final start = LiveReloadStart.run(() => throw StateError('bug'));

    expect(start, throwsA(isA<StateError>()));
  });
}
