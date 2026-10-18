import 'dart:async';
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:grund_cli/src/bundle/client_bundler.dart';
import 'package:grund_cli/src/dev/dev_bundle.dart';
import 'package:test/test.dart';

import 'helpers/fake_compile_runner.dart';
import 'helpers/temp_package.dart';

/// A runner whose compilation cannot even start.
final class _ThrowingRunner implements CompileRunner {
  @override
  Future<CompileOutcome> compileJs({
    required String entry,
    required String output,
    required bool release,
    required String workingDirectory,
  }) => throw const ProcessException('dart', ['compile'], 'not found', 2);
}

/// A runner whose compilations end when the test completes them.
final class _GatedRunner implements CompileRunner {
  final gates = <Completer<void>>[];
  final releases = <bool>[];

  @override
  Future<CompileOutcome> compileJs({
    required String entry,
    required String output,
    required bool release,
    required String workingDirectory,
  }) async {
    releases.add(release);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return const CompileOutcome(0, '');
  }
}

Future<TempPackage> _package({bool withEntry = true}) => TempPackage.create(
  'site',
  {if (withEntry) 'lib/main.client.dart': 'void main() {}'},
);

void main() {
  test('three requests during one build give exactly two builds', () async {
    final package = await _package();
    final runner = _GatedRunner();
    final bundle = DevBundle(
      ClientBundler(package.root, runner: runner),
      out: StringBuffer(),
    );

    bundle
      ..request()
      ..request()
      ..request();
    await pumpEventQueue();
    expect(runner.gates, hasLength(1));
    runner.gates[0].complete();
    await pumpEventQueue();
    expect(runner.gates, hasLength(2));
    runner.gates[1].complete();
    await bundle.settled;

    expect(runner.gates, hasLength(2));
    expect(runner.releases, [false, false]);
  });

  test('settled waits for the deferred build', () async {
    final package = await _package();
    final runner = _GatedRunner();
    final bundle = DevBundle(
      ClientBundler(package.root, runner: runner),
      out: StringBuffer(),
    );
    bundle
      ..request()
      ..request();
    var settled = false;
    unawaited(bundle.settled.then((_) => settled = true));

    await pumpEventQueue();
    runner.gates[0].complete();
    await pumpEventQueue();
    expect(settled, isFalse);
    runner.gates[1].complete();
    await pumpEventQueue();

    expect(settled, isTrue);
  });

  test('settled is complete when nothing builds', () async {
    final package = await _package();
    final bundle = DevBundle(
      ClientBundler(package.root, runner: FakeCompileRunner()),
      out: StringBuffer(),
    );

    await bundle.settled;
  });

  test(
    'a failing first build prints the compiler text and does not throw',
    () async {
      final package = await _package();
      final out = StringBuffer();
      final bundle = DevBundle(
        ClientBundler(package.root, runner: FakeCompileRunner(exitCode: 1)),
        out: out,
      );

      await bundle.initial();

      expect(out.toString(), contains('Client bundle failed'));
      expect(out.toString(), contains('Error: broken'));
    },
  );

  test('a successful build prints one line', () async {
    final package = await _package();
    final out = StringBuffer();
    final bundle = DevBundle(
      ClientBundler(package.root, runner: FakeCompileRunner()),
      out: out,
    );

    await bundle.initial();

    expect(
      out.toString(),
      matches(
        RegExp(r'^Bundled web/client/main\.client\.dart\.js in \d+ ms\.\n$'),
      ),
    );
  });

  test('without an entry nothing is compiled or printed', () async {
    final package = await _package(withEntry: false);
    final runner = FakeCompileRunner();
    final out = StringBuffer();
    final bundle = DevBundle(
      ClientBundler(package.root, runner: runner),
      out: out,
    );

    await bundle.initial();
    bundle.request();
    await bundle.settled;

    expect(runner.releases, isEmpty);
    expect(out.toString(), isEmpty);
  });

  test(
    'a runner that cannot start is a failed build; settled completes',
    () async {
      final package = await _package();
      final out = StringBuffer();
      final bundle = DevBundle(
        ClientBundler(package.root, runner: _ThrowingRunner()),
        out: out,
      );

      bundle.request();
      await bundle.settled;
      await bundle.initial();

      expect(out.toString(), contains('Client bundle failed'));
      expect(out.toString(), contains('not found'));
    },
  );
}
