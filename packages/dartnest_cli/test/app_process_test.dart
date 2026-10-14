import 'dart:async';
import 'dart:io';

import 'package:dartnest_cli/src/dev/app_process.dart';
import 'package:test/test.dart';

import 'helpers/line_sink.dart';
import 'helpers/temp_dir.dart';

/// Starts the Dart program [source] as an [AppProcess] in a [TempDir].
Future<(AppProcess, LineSink, LineSink)> startProgram(String source) async {
  final dir = TempDir.create();
  dir.write('bin/main.dart', source);
  final out = LineSink();
  final err = LineSink();
  final app = await AppProcess.start(
    target: 'bin/main.dart',
    arguments: ['an argument'],
    workingDirectory: dir.path,
    out: out,
    err: err,
  );
  addTearDown(() => app.stop(killGrace: Duration.zero));
  return (app, out, err);
}

void main() {
  test(
    'forwards the output of the child without the VM service banner',
    () async {
      final (app, out, err) = await startProgram('''
import 'dart:io';

void main(List<String> arguments) {
  print('started with \$arguments');
  stderr.writeln('a warning');
  exitCode = 3;
}
''');

      final uri = await app.serviceUri;
      expect(await app.exitCode, 3);
      expect(uri, isNotNull);
      expect(uri?.host, '127.0.0.1');
      expect(out.lines, ['started with [an argument]']);
      expect(err.lines, ['a warning']);
    },
  );

  test('the pid is the pid of the application', () async {
    final (app, out, _) = await startProgram('''
import 'dart:io';

void main() => print(pid);
''');

    await app.exitCode;
    expect(out.lines, ['${app.pid}']);
  });

  test('a child that cannot start has no VM service', () async {
    final dir = TempDir.create();
    final err = LineSink();
    final app = await AppProcess.start(
      target: 'bin/missing.dart',
      arguments: const [],
      workingDirectory: dir.path,
      out: LineSink(),
      err: err,
    );

    expect(await app.serviceUri, isNull);
    expect(await app.exitCode, isNot(0));
    expect(err.lines.join('\n'), contains('bin/missing.dart'));
  });

  test('stop ends a child that keeps running', () async {
    final (app, out, _) = await startProgram('''
Future<void> main() async {
  print('ready');
  await Future<void>.delayed(const Duration(hours: 1));
}
''');
    expect(await out.next(), 'ready');

    expect(await app.stop(), isNot(0));
  });

  test('stop kills a child that ignores SIGTERM', () async {
    // Review Focus 7: Windows has no SIGTERM; there stop only kills.
    final (app, out, _) = await startProgram('''
import 'dart:io';

void main() {
  ProcessSignal.sigterm.watch().listen((_) => print('ignored'));
  print('ready');
}
''');
    expect(await out.next(), 'ready');

    final code = await app.stop(killGrace: const Duration(milliseconds: 500));

    expect(code, -ProcessSignal.sigkill.signalNumber);
  }, testOn: '!windows');
}
