// The client bundle of the example compiles with the production flags of
// `grund bundle` (spec 4.4) and the server serves it under /static/client.
// Run with `dart test integration`; not part of `dart test` (slow).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:grund_cli/grund_cli.dart' show ProcessCompileRunner;
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import '../test/helpers/loopback_server.dart';

void main() {
  // The server resolves `web/` against the working directory, which is the
  // package root when the tests run as `dart test integration`.
  final packageRoot = Directory.current.path;
  final output = Directory('$packageRoot/web/client');
  // An existing output directory (ignored, regenerable) stays after the run.
  final outputExisted = output.existsSync();
  LoopbackServer? server; // Null until a test's setUp has started it.

  setUpAll(() async {
    expect(
      File('$packageRoot/lib/main.client.dart').existsSync(),
      isTrue,
      reason: 'run from the example package root: $packageRoot',
    );
    final compiled = await Process.run(
      Platform.resolvedExecutable,
      ProcessCompileRunner.arguments(
        entry: 'lib/main.client.dart',
        output: 'web/client/main.client.dart.js',
        release: true,
      ),
      workingDirectory: packageRoot,
    );
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
  });

  tearDownAll(() {
    if (outputExisted || !output.existsSync()) return;
    output.deleteSync(recursive: true);
  });

  setUp(() async {
    server = await LoopbackServer.start(ModuleStyle.explicit, AdapterKind.io);
  });

  tearDown(() async {
    final running = server;
    server = null;
    if (running == null) return;
    await running.close();
    expect(running.errors, isEmpty);
  });

  test('the compiled bundle is served as JavaScript', () async {
    final bundle = await server!.send(
      'GET',
      '/static/client/main.client.dart.js',
    );

    expect(bundle.status, 200);
    expect(bundle.headers['content-type'], contains('javascript'));
    // A minified dart2js program is far larger than any stub.
    expect(bundle.body.length, greaterThan(50000));
  });

  test('the page with the island loads the bundle', () async {
    final page = await server!.send('GET', '/');

    expect(
      page.body,
      contains('<script src="static/client/main.client.dart.js" defer>'),
    );
  });
}
