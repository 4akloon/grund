import 'dart:io';

import 'package:dartnest_cli/src/dev/dev_printer.dart';
import 'package:dartnest_cli/src/dev/dev_session.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:test/test.dart';

import 'helpers/hello_app.dart';
import 'helpers/line_sink.dart';

/// A [DevSession] of the `hello` application, fed by a real
/// [GenerationSession] as `dev` feeds it; the application's output and
/// what the session prints go to [lines].
final class Dev {
  Dev._(this.app, this.lines, this.generation, this.session);

  /// Creates the application and starts it through the first run.
  static Future<Dev> start() async {
    final app = await HelloApp.create();
    final lines = LineSink();
    final generation = GenerationSession(app.package.root);
    addTearDown(generation.close);
    final session = DevSession(
      app.package.root,
      target: app.package.dir.resolve('bin/main.dart'),
      arguments: const [],
      printer: DevPrinter('bin/main.dart', lines, lines),
      out: lines,
    );
    addTearDown(session.stop);
    final dev = Dev._(app, lines, generation, session);
    await dev.change(const []);
    return dev;
  }

  final HelloApp app;
  final LineSink lines;
  final GenerationSession generation;
  final DevSession session;

  /// Generates after a change of the package files [relative] and applies
  /// the run, as the watch loop of `dev` does.
  Future<void> change(List<String> relative) async {
    final changed = [
      for (final path in relative) app.package.dir.resolve(path),
    ];
    final report = await generation.run(changed: changed);
    await session.apply(changed, report);
  }

  /// Waits for the next `listening on <port>` line of the application.
  Future<int> listening() async {
    final line = await lines.nextWhere((line) => HelloApp.portIn(line) != null);
    return HelloApp.portIn(line) ?? 0;
  }

  /// The answer of `GET /hello` on [port].
  static Future<Map<String, Object?>> hello(int port) async =>
      await HelloApp.get(port, '/hello') as Map<String, Object?>;
}

void main() {
  test('a body change is reloaded in the same process', () async {
    final dev = await Dev.start();
    final port = await dev.listening();
    final before = await Dev.hello(port);

    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await dev.change(['lib/src/greeter.dart']);

    expect(dev.lines.lines.last, startsWith('Reloaded '));
    final after = await Dev.hello(port);
    expect(after, {'text': 'hello v2', 'pid': before['pid']});
  });

  test('a new field restarts the application in a new process', () async {
    // Review Focus 9: the old instances would keep a field they never
    // initialized; a restart builds them again.
    final dev = await Dev.start();
    final before = await Dev.hello(await dev.listening());

    dev.app.edit(
      'lib/src/greeter.dart',
      'String greet',
      'int count = 0;\n  String greet',
    );
    await dev.change(['lib/src/greeter.dart']);

    expect(
      dev.lines.lines,
      contains(
        'Restarting bin/main.dart: lib/src/greeter.dart changed a field, '
        'a constructor or a top-level variable.',
      ),
    );
    final after = await Dev.hello(await dev.listening());
    expect(after['pid'], isNot(before['pid']));
  });

  test('sources with problems keep the previous code running', () async {
    // Review Focus 3: a half-typed edit must not reach the application.
    final dev = await Dev.start();
    final port = await dev.listening();

    dev.app.edit('lib/src/greeter.dart', "'hello v1';", "'hello v2'");
    await dev.change(['lib/src/greeter.dart']);

    expect(
      dev.lines.lines.last,
      'bin/main.dart keeps running the previous code.',
    );
    expect((await Dev.hello(port))['text'], 'hello v1');

    dev.app.edit('lib/src/greeter.dart', "'hello v2'", "'hello v2';");
    await dev.change(['lib/src/greeter.dart']);
    expect((await Dev.hello(port))['text'], 'hello v2');
  });

  test('runs that arrive together are applied one after another', () async {
    // Review Focus 4: a storm of changes must not overlap two reloads.
    final dev = await Dev.start();
    final port = await dev.listening();
    final before = await Dev.hello(port);
    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    final changed = [dev.app.package.dir.resolve('lib/src/greeter.dart')];
    final report = await dev.generation.run(changed: changed);

    await Future.wait([
      for (var run = 0; run < 3; run++) dev.session.apply(changed, report),
    ]);

    final reloads = dev.lines.lines.where(
      (line) => line.startsWith('Reloaded'),
    );
    expect(reloads, hasLength(3));
    expect(await Dev.hello(port), {'text': 'hello v2', 'pid': before['pid']});
  });

  test('an application that exits starts again only after a change', () async {
    // Review Focus 5: a crashing application must not restart in a loop.
    final dev = await Dev.start();
    final pid = (await Dev.hello(await dev.listening()))['pid'] as int;

    Process.killPid(pid, ProcessSignal.sigkill);
    await dev.lines.nextWhere((line) => line.contains('exited with code'));
    expect(
      await dev.lines.after(const Duration(milliseconds: 500)),
      isNot(contains(startsWith('Started '))),
    );

    await dev.change(['lib/src/greeter.dart']);
    final again = await Dev.hello(await dev.listening());
    expect(again['pid'], isNot(pid));
  });

  test('stop ends the application and frees its port', () async {
    // Review Focus 1: no application process outlives dev.
    final dev = await Dev.start();
    final port = await dev.listening();

    await dev.session.stop();

    await expectLater(Dev.hello(port), throwsA(isA<SocketException>()));
  });
}
