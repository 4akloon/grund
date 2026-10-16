@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:grund_cli/grund_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test/helpers/hello_app.dart';
import '../test/helpers/line_sink.dart';
import 'helpers/dev_run.dart';

/// Starts `dev` of a new `hello` application on a free port.
Future<(HelloApp, DevRun)> startHello() async {
  final app = await HelloApp.create();
  final dev = await DevRun.start(app.package.dir.path, port: await freePort());
  return (app, dev);
}

void main() {
  // The roadmap's dev test: a body change keeps the process, a new route
  // appears, a new field restarts the application in a new process.
  test('dev reloads bodies and routes and restarts on a new field', () async {
    final (app, dev) = await startHello();
    final first = (await hello(dev.port))['pid'];

    app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await until(dev.lines, (line) => line.startsWith('Reloaded '));
    expect(await hello(dev.port), {'text': 'hello v2', 'pid': first});

    // Review Focus 8: the route reaches the application only through the
    // generated file, which is written before the reload.
    app.edit(
      'lib/src/hello_api.dart',
      "  @Get('/')",
      "  @Get('/bye')\n  Map<String, Object> bye() => {'text': 'bye'};\n\n"
          "  @Get('/')",
    );
    await until(dev.lines, (line) => line.endsWith(', 1 added, 0 removed.'));
    await until(dev.lines, (line) => line == '  + GET /hello/bye');
    expect(await HelloApp.get(dev.port, '/hello/bye'), {'text': 'bye'});
    expect((await hello(dev.port))['pid'], first);

    // Review Focus 6: the new process binds the port the old one held.
    app.edit(
      'lib/src/greeter.dart',
      'String greet',
      'int count = 0;\n\n  String greet',
    );
    await until(dev.lines, (line) => line.startsWith('Restarting '));
    await until(dev.lines, isListening, count: 2);
    final second = (await hello(dev.port))['pid'];
    expect(second, isNot(first));

    dev.keys.add('R');
    await until(dev.lines, (line) => line.endsWith(': restart requested.'));
    await until(dev.lines, isListening, count: 3);
    expect((await hello(dev.port))['pid'], allOf(isNot(first), isNot(second)));

    expect(await dev.stop(), CliExitCode.success.code);
    // Review Focus 1: the application ended with dev.
    await expectLater(hello(dev.port), throwsA(isA<SocketException>()));
  });

  test('a storm of saves ends with the last version in one process', () async {
    // Review Focus 4.
    final (app, dev) = await startHello();
    final first = (await hello(dev.port))['pid'];

    for (var version = 2; version <= 6; version++) {
      app.edit(
        'lib/src/greeter.dart',
        'hello v${version - 1}',
        'hello v$version',
      );
    }
    final stopwatch = Stopwatch()..start();
    while ((await hello(dev.port))['text'] != 'hello v6') {
      if (stopwatch.elapsed > const Duration(seconds: 30)) fail('No v6.');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect((await hello(dev.port))['pid'], first);
    expect(dev.lines.lines, isNot(contains(startsWith('Restarting '))));
    expect(dev.lines.lines, isNot(contains(contains('failed'))));
  });

  test('a compile error in bin/ keeps the previous code running', () async {
    final (app, dev) = await startHello();

    app.edit('bin/main.dart', 'final adapter', 'final adapter = 1;\n  var');
    await until(dev.lines, (line) => line.startsWith('Hot reload failed; '));
    expect((await hello(dev.port))['text'], 'hello v1');
  });

  test('SIGTERM stops dev and the application with it', () async {
    // Review Focus 1 and 7: a supervisor stops dev with SIGTERM outside
    // Windows; the application must not outlive it.
    final app = await HelloApp.create();
    final port = await freePort();
    final cli = await Isolate.resolvePackageUri(
      Uri.parse('package:grund_cli/'),
    );
    final script = p.join(
      p.dirname(p.fromUri(cli ?? Uri())),
      'bin',
      'grund_cli.dart',
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      script,
      'dev',
      '-C',
      app.package.dir.path,
      '--',
      '$port',
    ]);
    final lines = LineSink();
    addTearDown(() => killStrays(lines));
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    process.stdout.transform(utf8.decoder).listen(lines.write);
    process.stderr.transform(utf8.decoder).listen(lines.write);
    await until(lines, isListening);
    expect((await hello(port))['text'], 'hello v1');

    process.kill(ProcessSignal.sigterm);

    expect(
      await process.exitCode.timeout(const Duration(seconds: 30)),
      CliExitCode.success.code,
    );
    await expectLater(hello(port), throwsA(isA<SocketException>()));
  }, testOn: '!windows');

  test('a failing run ends the dev process with 70, not a hang', () async {
    final app = await HelloApp.create();
    final script = p.join(
      Directory.current.path,
      'integration',
      'fixtures',
      'failing_dev.dart',
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      script,
      'dev',
      '-C',
      app.package.dir.path,
    ]);
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    final err = StringBuffer();
    process.stdout.drain<void>();
    process.stderr.transform(utf8.decoder).listen(err.write);

    final code = await process.exitCode.timeout(const Duration(seconds: 60));

    expect(code, CliExitCode.software.code);
    expect(err.toString(), contains('dev stopped: FormatException: boom'));
  }, testOn: '!windows');
}
