import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test/helpers/hello_app.dart';
import '../test/helpers/line_sink.dart';

/// Waits until [lines] has [count] lines that satisfy [test], in any order
/// with the other lines (the application prints while dev does).
Future<void> until(
  LineSink lines,
  bool Function(String line) test, {
  int count = 1,
}) async {
  while (lines.lines.where(test).length < count) {
    await lines.next();
  }
}

bool isListening(String line) => HelloApp.portIn(line) != null;

/// Kills the application processes `dev` reported in [lines] (`Started ...
/// (pid N`) that are still running, so a failing test leaves none behind.
void killStrays(LineSink lines) {
  final started = RegExp(r'^Started .* \(pid (\d+),');
  for (final line in lines.lines) {
    final pid = int.tryParse(started.firstMatch(line)?[1] ?? '');
    if (pid == null || !_isApplication(pid)) continue;
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

// The pid may have been reused after a clean shutdown; where /proc tells
// what it runs, only a child VM with the VM service is killed.
bool _isApplication(int pid) {
  final command = File('/proc/$pid/cmdline');
  return !command.existsSync() ||
      command.readAsStringSync().contains('--enable-vm-service');
}

/// A loopback port that was free a moment ago.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// The answer of `GET /hello` on [port].
Future<Map<String, Object?>> hello(int port) async =>
    await HelloApp.get(port, '/hello') as Map<String, Object?>;

/// `dev` of the `hello` application on [port], run in-process.
final class DevRun {
  DevRun._(this.app, this.port, this.lines, this.keys, this._stop, this.exit);

  /// Starts `dev` and waits until the application listens.
  static Future<DevRun> start() async {
    final app = await HelloApp.create();
    final port = await freePort();
    final lines = LineSink();
    final keys = StreamController<String>();
    final stop = Completer<void>();
    final exit = DartnestCli(
      out: lines,
      err: lines,
      interruption: Interruption(untilStopped: () => stop.future),
      keys: () => keys.stream,
    ).run(['dev', '-C', app.package.dir.path, '--', '$port']);
    final run = DevRun._(app, port, lines, keys, stop, exit);
    addTearDown(() => killStrays(lines));
    addTearDown(run.stop);
    await until(lines, (line) => line.startsWith('Watching lib/ and bin/'));
    await until(lines, isListening);
    return run;
  }

  final HelloApp app;
  final int port;
  final LineSink lines;
  final StreamController<String> keys;
  final Completer<void> _stop;

  /// The exit code of `dev`.
  final Future<int> exit;

  /// Stops `dev` as Ctrl+C does and returns its exit code.
  Future<int> stop() {
    if (!_stop.isCompleted) _stop.complete();
    return exit;
  }
}

void main() {
  // The roadmap's dev test: a body change keeps the process, a new route
  // appears, a new field restarts the application in a new process.
  test('dev reloads bodies and routes and restarts on a new field', () async {
    final dev = await DevRun.start();
    final first = (await hello(dev.port))['pid'];

    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await until(dev.lines, (line) => line.startsWith('Reloaded '));
    expect(await hello(dev.port), {'text': 'hello v2', 'pid': first});

    // Review Focus 8: the route reaches the application only through the
    // generated file, which is written before the reload.
    dev.app.edit(
      'lib/src/hello_controller.dart',
      '  @Get()',
      "  @Get('/bye')\n  Map<String, Object> bye() => {'text': 'bye'};\n\n"
          '  @Get()',
    );
    await until(dev.lines, (line) => line.endsWith(', 1 route changed.'));
    expect(await HelloApp.get(dev.port, '/hello/bye'), {'text': 'bye'});
    expect((await hello(dev.port))['pid'], first);

    // Review Focus 6: the new process binds the port the old one held.
    dev.app.edit(
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
    final dev = await DevRun.start();
    final first = (await hello(dev.port))['pid'];

    for (var version = 2; version <= 6; version++) {
      dev.app.edit(
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
    final dev = await DevRun.start();

    dev.app.edit('bin/main.dart', 'final adapter', 'final adapter = 1;\n  var');
    await until(dev.lines, (line) => line.startsWith('Hot reload failed; '));
    expect((await hello(dev.port))['text'], 'hello v1');
  });

  test('SIGTERM stops dev and the application with it', () async {
    // Review Focus 1 and 7: a supervisor stops dev with SIGTERM outside
    // Windows; the application must not outlive it.
    final app = await HelloApp.create();
    final port = await freePort();
    final cli = await Isolate.resolvePackageUri(
      Uri.parse('package:dartnest_cli/'),
    );
    final script = p.join(
      p.dirname(p.fromUri(cli ?? Uri())),
      'bin',
      'dartnest_cli.dart',
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
}
