// The client bundle of the example compiles with the production flags of
// `grund bundle` (spec 4.4) and the server serves it under /static/client.
// Run with `dart test integration`; not part of `dart test` (slow).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import '../test/helpers/loopback_server.dart';

void main() {
  late LoopbackServer server; // Set in setUp after the bundle was built.

  setUp(() async {
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-O2',
      '-Djaspr.flags.release=true',
      '-o',
      'web/client/main.client.dart.js',
      'lib/main.client.dart',
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    server = await LoopbackServer.start(ModuleStyle.explicit, AdapterKind.io);
  });

  tearDown(() async {
    await server.close();
    final output = Directory('web/client');
    if (output.existsSync()) output.deleteSync(recursive: true);
    expect(server.errors, isEmpty);
  });

  test('the compiled bundle is served as JavaScript', () async {
    final bundle = await server.send(
      'GET',
      '/static/client/main.client.dart.js',
    );

    expect(bundle.status, 200);
    expect(bundle.headers['content-type'], contains('javascript'));
    expect(bundle.body, isNotEmpty);
  });

  test('the page with the island loads the bundle', () async {
    final page = await server.send('GET', '/');

    expect(
      page.body,
      contains('<script src="static/client/main.client.dart.js" defer>'),
    );
  });
}
