import 'package:dartnest_cli/src/dev/app_process.dart';
import 'package:dartnest_cli/src/dev/reload_client.dart';
import 'package:dartnest_cli/src/dev/reload_result.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:test/test.dart';

import 'helpers/hello_app.dart';
import 'helpers/line_sink.dart';

/// The running `hello` application with a connected [ReloadClient].
final class Running {
  Running._(this.app, this.process, this.client, this.port, this.err);

  /// Starts the application and waits until it listens.
  static Future<Running> start() async {
    final app = await HelloApp.create();
    final out = LineSink();
    final err = LineSink();
    final process = await AppProcess.start(
      target: 'bin/main.dart',
      arguments: const [],
      workingDirectory: app.package.dir.path,
      out: out,
      err: err,
    );
    addTearDown(() => process.stop(killGrace: Duration.zero));
    final uri = await process.serviceUri;
    final client = uri == null ? null : await ReloadClient.connect(uri);
    if (client == null) throw StateError('No VM service: ${err.lines}');
    addTearDown(client.dispose);
    final port = HelloApp.portIn(await out.next());
    if (port == null) throw StateError('Not listening: ${out.lines}');
    return Running._(app, process, client, port, err);
  }

  final HelloApp app;
  final AppProcess process;
  final ReloadClient client;
  final int port;
  final LineSink err;

  /// Generates the package again, as `dev` does before a reload.
  Future<void> regenerate() async {
    final session = GenerationSession(app.package.root);
    try {
      await session.run();
    } finally {
      await session.close();
    }
  }
}

void main() {
  test('a changed method body is reloaded and reassembled', () async {
    final running = await Running.start();
    running.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');

    final result = await running.client.reload();

    expect(result, isA<Reloaded>());
    final reloaded = result as Reloaded;
    expect(reloaded.libraries, greaterThan(0));
    expect(reloaded.changedRoutes, 0);
    expect(reloaded.reassembleError, isNull);
    expect(await HelloApp.get(running.port, '/hello'), {
      'text': 'hello v2',
      'pid': running.process.pid,
    });
  });

  test('a compile error fails the reload and keeps the old code', () async {
    final running = await Running.start();
    running.app.edit('lib/src/greeter.dart', "'hello v1'", "'hello v1' +");

    final result = await running.client.reload();

    expect(result, isA<ReloadFailed>());
    expect((result as ReloadFailed).message, contains('Error:'));
    expect(
      await HelloApp.get(running.port, '/hello'),
      containsPair('text', 'hello v1'),
    );
  });

  test('a change hot reload cannot apply is rejected', () async {
    final running = await Running.start();
    running.app.edit(
      'lib/src/greeter.dart',
      'class Greeter {',
      'class Greeter<T> {',
    );

    final result = await running.client.reload();

    expect(result, isA<ReloadRejected>());
    expect((result as ReloadRejected).reason, contains('type parameters'));
  });

  test('a failing reassemble is reported and the old state serves', () async {
    final running = await Running.start();
    running.app.package.dir.write('lib/src/broken.dart', '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Broken {
  Broken() {
    throw StateError('broken provider');
  }
}
''');
    running.app.edit(
      'lib/src/app_module.dart',
      '[Greeter]',
      '[Greeter, Broken]',
    );
    running.app.edit(
      'lib/src/app_module.dart',
      "import 'greeter.dart';",
      "import 'broken.dart';\nimport 'greeter.dart';",
    );
    await running.regenerate();

    final result = await running.client.reload();

    expect(result, isA<Reloaded>());
    expect((result as Reloaded).reassembleError, contains('broken provider'));
    expect(
      await HelloApp.get(running.port, '/hello'),
      containsPair('text', 'hello v1'),
    );
  });

  test('closing the applications lets the process exit', () async {
    final running = await Running.start();

    await running.client.closeApplications();

    expect(await running.process.exitCode, 0);
  });
}
