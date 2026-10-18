@TestOn('vm')
// The first child `dart run` compiles the application cold (a fresh CI
// runner needs far more than the default 30 s); the bodies bound the waits.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Binds every address that `localhost` resolves to on one shared port, so
/// the application collides whichever of them it picks (a runner may list
/// `::1` first, where a blocker on 127.0.0.1 alone would not collide).
Future<List<ServerSocket>> _blockLocalhost() async {
  final addresses = await InternetAddress.lookup('localhost');
  final first = await ServerSocket.bind(addresses.first, 0);
  final blockers = [first];
  for (final address in addresses.skip(1)) {
    blockers.add(await ServerSocket.bind(address, first.port, v6Only: true));
  }
  return blockers;
}

Future<Process> _start(int port) => Process.start(
  Platform.resolvedExecutable,
  ['run', 'bin/main.dart'],
  environment: {'HOST': 'localhost', 'PORT': '$port'},
);

void main() {
  test(
    'a port in use: one line of its own on stderr and exit code 1',
    () async {
      final blockers = await _blockLocalhost();
      addTearDown(() => Future.wait(blockers.map((socket) => socket.close())));

      final process = await _start(blockers.first.port);
      addTearDown(process.kill);
      final err = process.stderr.transform(utf8.decoder).join();
      unawaited(process.stdout.drain<void>());

      expect(await process.exitCode.timeout(const Duration(seconds: 60)), 1);
      // The application logs the rollback as one WARNING line (grund.app);
      // main adds exactly one line of its own, the last. The missing client
      // bundle warning (grund.jaspr) is expected: the test does not build it.
      final lines = (await err).trim().split('\n');
      expect(
        lines.last,
        startsWith('Cannot start: '),
        reason: lines.join('\n'),
      );
      expect(
        lines.where(
          (line) =>
              !line.contains('[grund.app]') && !line.contains('[grund.jaspr]'),
        ),
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
