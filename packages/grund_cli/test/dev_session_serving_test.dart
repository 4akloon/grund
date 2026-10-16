import 'dart:async';

import 'package:test/test.dart';

import 'helpers/dev.dart';

/// Counts the calls of a callback and lets a test wait for the next one.
final class Calls {
  Calls({this.probe});

  /// Observed at every call; its results are in [probes].
  final int Function()? probe;
  final probes = <int>[];
  var count = 0;
  final _calls = StreamController<int>.broadcast();
  void call() {
    if (probe case final observe?) probes.add(observe());
    _calls.add(++count);
  }

  Future<void> reach(int n) async {
    if (count >= n) return;
    await _calls.stream
        .firstWhere((c) => c >= n)
        .timeout(const Duration(seconds: 30));
  }
}

void main() {
  test('a started application announces once it serves', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await dev.listening();

    await served.reach(1);
    expect(served.count, 1);
  });

  test('a reload announces after the reassemble', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await served.reach(1);

    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await dev.change(['lib/src/greeter.dart']);

    expect(served.count, 2);
  });

  test('a restart announces once the new process serves', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    final before = await Dev.hello(await dev.listening());
    await served.reach(1);

    dev.app.edit(
      'lib/src/greeter.dart',
      'String greet',
      'int count = 0;\n  String greet',
    );
    await dev.change(['lib/src/greeter.dart']);
    final after = await Dev.hello(await dev.listening());

    await served.reach(2);
    expect(after['pid'], isNot(before['pid']));
  });

  test('sources with problems announce nothing', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await served.reach(1);

    dev.app.edit('lib/src/greeter.dart', "'hello v1';", "'hello v2'");
    await dev.change(['lib/src/greeter.dart']);

    expect(dev.lines.lines, contains(contains('keeps running')));
    expect(served.count, 1);
  });

  test('a failed reload announces nothing', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await served.reach(1);

    dev.app.edit('lib/src/greeter.dart', "'hello v1'", "'hello v1' + 1");
    await dev.change(['lib/src/greeter.dart']);

    expect(served.count, 1);
  });

  test('a failed reassemble announces nothing', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await served.reach(1);
    dev.app.package.dir.write('lib/src/broken.dart', _brokenProvider);
    dev.app
      ..edit('lib/src/app_module.dart', '[Greeter, HelloApi]', _withBroken)
      ..edit(
        'lib/src/app_module.dart',
        "import 'greeter.dart';",
        "import 'broken.dart';\nimport 'greeter.dart';",
      );

    await dev.change(['lib/src/app_module.dart', 'lib/src/broken.dart']);

    expect(dev.lines.lines, contains(contains('broken provider')));
    expect(served.count, 1);
  });

  test(
    'a rejected reload announces only once the new process serves',
    () async {
      Dev? dev; // Null until Dev.start returns; no announcement needs it then.
      final served = Calls(
        probe: () =>
            dev?.lines.lines
                .where((line) => line.startsWith('Started'))
                .length ??
            0,
      );
      dev = await Dev.start(
        onServing: served.call,
        prepare: (app) => app.edit(
          'lib/src/greeter.dart',
          "String greet() => 'hello v1';\n}",
          "final plain = Plain();\n\n  String greet() => 'hello v1';\n}\n\n"
              'class Plain {}',
        ),
      );
      await served.reach(1);

      // Type parameters of a class with a live instance are a change hot
      // reload cannot apply. The file is not listed as changed, so the
      // shape check does not restart first.
      dev.app.edit(
        'lib/src/greeter.dart',
        'class Plain {}',
        'class Plain<T> {}',
      );
      await dev.change(const []);
      await served.reach(2);

      // The second announcement comes after the second `Started` line, not
      // right after the rejection.
      expect(served.probes.last, 2);
    },
  );
}

const _withBroken = '[Greeter, HelloApi, Broken]';

const _brokenProvider = '''
import 'package:grund/annotations.dart';

@Injectable()
final class Broken {
  Broken() {
    throw StateError('broken provider');
  }
}
''';
