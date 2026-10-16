import 'package:grund_cli/src/dev/app_command.dart';
import 'package:grund_cli/src/dev/app_process.dart';
import 'package:grund_cli/src/dev/reload_client.dart';
import 'package:grund_cli/src/dev/reload_result.dart';
import 'package:grund_cli/src/dev/reload_timeouts.dart';
import 'package:test/test.dart';

import 'helpers/hung_vm_service.dart';
import 'helpers/line_sink.dart';
import 'helpers/temp_dir.dart';

const _short = ReloadTimeouts(
  connect: Duration(milliseconds: 300),
  reload: Duration(milliseconds: 300),
  close: Duration(milliseconds: 300),
  serving: Duration(milliseconds: 300),
);

/// Starts a Dart program without grund that keeps running, and connects
/// to it with [timeouts].
Future<ReloadClient> _clientOfProcessWithoutGrund({
  ReloadTimeouts timeouts = const ReloadTimeouts(),
}) async {
  final dir = TempDir.create();
  final entry = dir.write(
    'main.dart',
    "import 'dart:async';\n\n"
        "void main() {\n  Timer(const Duration(minutes: 5), () {});\n"
        "  print('up');\n}\n",
  );
  final process = await AppProcess.start(
    AppCommand(entry, workingDirectory: dir.path),
    out: LineSink(),
    err: LineSink(),
  );
  addTearDown(() => process.stop(killGrace: Duration.zero));
  final uri = await process.serviceUri ?? fail('No VM service.');
  final client = await ReloadClient.connect(uri, timeouts: timeouts);
  if (client == null) fail('No connection.');
  addTearDown(client.dispose);
  return client;
}

/// Connects to a VM service that opens the connection and never answers.
Future<ReloadClient> _connectedToHungService() async {
  final service = await HungVmService.start(webSocket: true);
  final client = await ReloadClient.connect(service.uri, timeouts: _short);
  return client ?? fail('The connection should have opened.');
}

void main() {
  test('connecting to a port nobody listens on gives null', () async {
    final uri = Uri.parse('http://127.0.0.1:${await deadPort()}/token=/');

    expect(await ReloadClient.connect(uri, timeouts: _short), isNull);
  });

  test('a handshake that never completes gives null in time', () async {
    final service = await HungVmService.start(webSocket: false);
    final stopwatch = Stopwatch()..start();

    final client = await ReloadClient.connect(service.uri, timeouts: _short);

    expect(client, isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('a reload the VM service never answers is a failure', () async {
    final client = await _connectedToHungService();

    final result = await client.reload();

    expect(result, isA<ReloadFailed>());
    expect((result as ReloadFailed).message, contains('timed out'));
  });

  test('closing applications on a hung VM service gives up', () async {
    final client = await _connectedToHungService();

    await client.closeApplications();
    await client.dispose();
  });

  test('a process without grund reloads and skips the reassemble', () async {
    final client = await _clientOfProcessWithoutGrund();

    final result = await client.reload();

    expect(result, isA<Reloaded>());
    expect((result as Reloaded).changes, isNull);
    expect(result.reassembleError, isNull);
  });

  test('a process without grund never serves', () async {
    final client = await _clientOfProcessWithoutGrund(timeouts: _short);

    expect(await client.waitUntilServing(), isFalse);
  });

  test('a VM service that never answers never serves', () async {
    final client = await _connectedToHungService();
    addTearDown(client.dispose);

    expect(await client.waitUntilServing(), isFalse);
  });
}
