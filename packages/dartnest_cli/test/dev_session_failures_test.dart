import 'dart:io';

import 'package:test/test.dart';

import 'helpers/dev.dart';
import 'helpers/hello_app.dart';
import 'helpers/failing_launcher.dart';

const _greeter = 'lib/src/greeter.dart';
const _controller = 'lib/src/hello_controller.dart';
const _newField = 'int count = 0;\n  String greet';

void main() {
  test('a shape change in a run with problems restarts on the fix', () async {
    final dev = await Dev.start();
    final before = await Dev.hello(await dev.listening());
    dev.app.edit(_greeter, 'String greet', _newField);
    dev.app.edit(_controller, 'greeter.greet()', 'greeter.greet(');

    await dev.change([_greeter, _controller]);
    expect(
      dev.lines.lines.last,
      'bin/main.dart keeps running the previous code.',
    );
    dev.app.edit(_controller, 'greeter.greet(', 'greeter.greet()');
    await dev.change([_controller]);

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

  test('operations queued behind stop do nothing', () async {
    final dev = await Dev.start();
    final port = await dev.listening();
    dev.app.edit(_greeter, 'String greet', _newField);
    final changed = [dev.app.package.dir.resolve(_greeter)];
    final report = await dev.generation.run(changed: changed);

    await Future.wait([
      dev.session.apply(changed, report),
      dev.session.stop(),
      dev.session.restart(),
      dev.session.reload(),
    ]);

    expect(dev.lines.lines.where((l) => l.startsWith('Restarting')), isEmpty);
    expect(dev.lines.lines.where((l) => l.startsWith('Started')), hasLength(1));
    await expectLater(Dev.hello(port), throwsA(isA<SocketException>()));
  });

  test('a failing connect stops the process it started', () async {
    final launcher = FailingLauncher(connectFails: true);
    final dev = await Dev.create(launcher: launcher);

    await expectLater(dev.change(const []), throwsA(isA<StateError>()));

    expect(launcher.started, hasLength(1));
    await launcher.started.single.exitCode.timeout(const Duration(seconds: 10));
  });

  test('a failing close still ends the process', () async {
    final launcher = FailingLauncher(closeFails: true);
    final dev = await Dev.start(launcher: launcher);
    await dev.listening();

    await expectLater(dev.session.stop(), throwsA(isA<StateError>()));

    await launcher.started.single.exitCode.timeout(const Duration(seconds: 10));
  });

  test('a rejected reload restarts in a new process', () async {
    final dev = await Dev.start(prepare: _addExtra);
    final before = await Dev.hello(await dev.listening());

    dev.app.edit('tool/extra.dart', 'class Extra {}', 'class Extra<T> {}');
    await dev.change(['tool/extra.dart']);

    await dev.lines.nextWhere(
      (line) => line.startsWith('Restarting bin/main.dart: hot reload is not'),
    );
    final after = await Dev.hello(await dev.listening());
    expect(after['pid'], isNot(before['pid']));
  });

  test('r with nothing running starts, R restarts', () async {
    final dev = await Dev.start();
    final pid = (await Dev.hello(await dev.listening()))['pid'] as int;
    Process.killPid(pid, ProcessSignal.sigkill);
    await dev.lines.nextWhere((line) => line.contains('exited with code'));

    await dev.session.reload();
    final started = (await Dev.hello(await dev.listening()))['pid'] as int;
    await dev.session.restart();

    expect(
      dev.lines.lines,
      contains('Restarting bin/main.dart: restart requested.'),
    );
    final restarted = (await Dev.hello(await dev.listening()))['pid'];
    expect(started, isNot(pid));
    expect(restarted, isNot(started));
  });

  test('a launch that fails to compile prints exited and stops', () async {
    final dev = await Dev.start();
    final pid = (await Dev.hello(await dev.listening()))['pid'] as int;
    Process.killPid(pid, ProcessSignal.sigkill);
    await dev.lines.nextWhere((line) => line.contains('exited with code'));
    dev.app.edit('bin/main.dart', 'main(List', 'main(List<');

    await dev.change([_greeter]);

    await dev.lines.nextWhere((line) => line.contains('exited with code'));
    final quiet = await dev.lines.after(const Duration(milliseconds: 500));
    expect(quiet.where((l) => l.startsWith('Started ')), isEmpty);
  });

  test('losing the VM service connection is its own message', () async {
    final dev = await Dev.start(launcher: FailingLauncher(connectNull: true));

    expect(
      dev.lines.lines,
      contains(
        'bin/main.dart: could not connect to the VM service; stopped the '
        'application, it starts again after the next change.',
      ),
    );
  });
}

void _addExtra(HelloApp app) {
  app.package.dir.write(
    'tool/extra.dart',
    'class Extra {}\n\nfinal kept = Extra();\n',
  );
  app.edit(
    'bin/main.dart',
    "import 'dart:io';",
    "import 'dart:io';\nimport '../tool/extra.dart';",
  );
  app.edit('bin/main.dart', 'final adapter', 'print(kept);\n  final adapter');
}
