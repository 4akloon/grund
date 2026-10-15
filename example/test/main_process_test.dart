@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<Process> _start(int port) => Process.start(
  Platform.resolvedExecutable,
  ['run', 'bin/main.dart'],
  environment: {'PORT': '$port'},
);

void main() {
  test(
    'a port in use: one line of its own on stderr and exit code 1',
    () async {
      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(blocker.close);

      final process = await _start(blocker.port);
      final err = process.stderr.transform(utf8.decoder).join();
      unawaited(process.stdout.drain<void>());

      expect(await process.exitCode.timeout(const Duration(seconds: 60)), 1);
      // The application logs the rollback as one WARNING line (grund.app);
      // main adds exactly one line of its own, the last.
      final lines = (await err).trim().split('\n');
      expect(
        lines.last,
        startsWith('Cannot start: '),
        reason: lines.join('\n'),
      );
      expect(
        lines.where((line) => !line.contains('[grund.app]')),
        hasLength(1),
        reason: lines.join('\n'),
      );
      expect(lines.join(), isNot(contains('Unhandled exception')));
    },
    skip: Platform.isWindows ? 'process test' : null,
  );

  test('SIGTERM closes gracefully with exit code 0', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final process = await _start(port);
    addTearDown(process.kill);
    unawaited(process.stderr.drain<void>());
    // Keep reading after the line: a closed pipe would make the log output
    // of the shutdown fail.
    final listening = Completer<void>();
    process.stdout.transform(utf8.decoder).listen((chunk) {
      if (chunk.contains('listening') && !listening.isCompleted) {
        listening.complete();
      }
    });
    await listening.future.timeout(const Duration(seconds: 60));

    process.kill(ProcessSignal.sigterm);

    expect(await process.exitCode.timeout(const Duration(seconds: 30)), 0);
  }, skip: Platform.isWindows ? 'no SIGTERM on Windows' : null);
}
