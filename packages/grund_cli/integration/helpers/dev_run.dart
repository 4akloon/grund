import 'dart:async';
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import '../../test/helpers/hello_app.dart';
import '../../test/helpers/line_sink.dart';

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

/// `dev` of the application in a package directory, serving on [port],
/// run in-process.
final class DevRun {
  DevRun._(this.port, this.lines, this.keys, this._stop, this.exit);

  /// Starts `dev` of the package in [directory], passing [port] to `main`,
  /// and waits until the application prints `listening on <port>`.
  static Future<DevRun> start(String directory, {required int port}) async {
    final lines = LineSink();
    final keys = StreamController<String>();
    final stop = Completer<void>();
    final exit = GrundCli(
      out: lines,
      err: lines,
      host: CliHost(
        interruption: Interruption(untilStopped: () => stop.future),
        keys: () => keys.stream,
      ),
    ).run(['dev', '-C', directory, '--', '$port']);
    final run = DevRun._(port, lines, keys, stop, exit);
    addTearDown(() => killStrays(lines));
    addTearDown(run.stop);
    await until(lines, (line) => line.startsWith('Watching lib/ and bin/'));
    await until(lines, isListening);
    return run;
  }

  /// The port the application serves on.
  final int port;

  /// What `dev` and the application printed.
  final LineSink lines;

  /// The terminal keys `dev` reads.
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
