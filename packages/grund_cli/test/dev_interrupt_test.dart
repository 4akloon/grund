import 'dart:async';
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/hello_app.dart';
import 'helpers/line_sink.dart';

/// The pid in a `Started ... (pid N, ...)` line.
int? _pidIn(String line) {
  final match = RegExp(r'^Started .* \(pid (\d+),').firstMatch(line);
  return match == null ? null : int.parse(match[1] ?? '');
}

void main() {
  test('a second interrupt while dev shuts down exits 130 at once', () async {
    final app = await HelloApp.create();
    final lines = LineSink();
    final signals = StreamController<void>.broadcast();
    final exits = <int>[];
    final done = GrundCli(
      out: lines,
      err: lines,
      host: CliHost(
        interruption: Interruption(
          signals: () => signals.stream,
          forceExit: exits.add,
        ),
        keys: () => const Stream<String>.empty(),
      ),
    ).run(['dev', '-C', app.package.dir.path]);
    final started = await lines.nextWhere((line) => _pidIn(line) != null);
    final pid = _pidIn(started) ?? 0;
    addTearDown(() => Process.killPid(pid, ProcessSignal.sigkill));

    signals.add(null);
    await Future<void>.delayed(Duration.zero);
    signals.add(null);

    expect(await done, CliExitCode.success.code);
    expect(exits, [CliExitCode.interrupted.code]);
    expect(Process.killPid(pid, ProcessSignal.sigcont), isFalse);
  }, testOn: '!windows');

  test('the first interrupt alone does not force an exit', () async {
    final app = await HelloApp.create();
    final lines = LineSink();
    final signals = StreamController<void>.broadcast();
    final exits = <int>[];
    final done = GrundCli(
      out: lines,
      err: lines,
      host: CliHost(
        interruption: Interruption(
          signals: () => signals.stream,
          forceExit: exits.add,
        ),
        keys: () => const Stream<String>.empty(),
      ),
    ).run(['dev', '-C', app.package.dir.path]);
    await lines.nextWhere((line) => _pidIn(line) != null);

    signals.add(null);

    expect(await done, CliExitCode.success.code);
    expect(exits, isEmpty);
  });
}
