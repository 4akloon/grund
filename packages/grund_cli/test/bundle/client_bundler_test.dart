import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:grund_cli/src/bundle/bundle_result.dart';
import 'package:grund_cli/src/bundle/client_bundler.dart';
import 'package:test/test.dart';

import '../helpers/fake_compile_runner.dart';
import '../helpers/temp_package.dart';

const _stale = [
  'web/client/main.client.dart.js',
  'web/client/main.client.dart.js_1.part.js',
  'web/client/main.client.dart.js.gz',
  'web/client/main.client.dart.js.br',
];

Future<TempPackage> _package() => TempPackage.create('site', {
  'lib/main.client.dart': 'void main() {}',
  'web/client/keep.txt': 'keep',
  for (final file in _stale) file: 'old',
});

void main() {
  test(
    'a build puts the bundle in place and removes the stale files',
    () async {
      final package = await _package();
      final bundler = ClientBundler(
        package.root,
        runner: FakeCompileRunner(files: ['{output}']),
      );

      final result = await bundler.build(release: true);

      expect(result, isA<BundleBuilt>());
      expect(package.dir.read('web/client/main.client.dart.js'), 'new');
      for (final stale in _stale.skip(1)) {
        expect(package.dir.exists(stale), isFalse, reason: stale);
      }
      expect(package.dir.exists('web/client/keep.txt'), isTrue);
    },
  );

  test('a failed build leaves the old bundle untouched', () async {
    final package = await _package();
    final bundler = ClientBundler(
      package.root,
      runner: FakeCompileRunner(exitCode: 1),
    );

    final result = await bundler.build(release: true);

    expect(result, isA<BundleFailed>());
    expect((result as BundleFailed).output, contains('broken'));
    for (final stale in _stale) {
      expect(package.dir.read(stale), 'old', reason: stale);
    }
  });

  test(
    'release passes the production mode and keeps no maps or deps',
    () async {
      final package = await _package();
      final runner = FakeCompileRunner();

      await ClientBundler(package.root, runner: runner).build(release: true);

      expect(runner.releases, [true]);
      expect(package.dir.exists('web/client/main.client.dart.js'), isTrue);
      expect(package.dir.exists('web/client/main.client.dart.js.map'), isFalse);
      expect(
        package.dir.exists('web/client/main.client.dart.js.deps'),
        isFalse,
      );
    },
  );

  test('a development build passes -O1 mode and keeps the map', () async {
    final package = await _package();
    final runner = FakeCompileRunner();

    await ClientBundler(package.root, runner: runner).build(release: false);

    expect(runner.releases, [false]);
    expect(package.dir.exists('web/client/main.client.dart.js.map'), isTrue);
    expect(package.dir.exists('web/client/main.client.dart.js.deps'), isFalse);
  });

  test('without the entry the build is skipped', () async {
    final package = await TempPackage.create('site');
    final runner = FakeCompileRunner();
    final bundler = ClientBundler(package.root, runner: runner);

    final result = await bundler.build(release: true);

    expect(bundler.hasEntry, isFalse);
    expect(result, isA<BundleSkipped>());
    expect(runner.releases, isEmpty);
  });

  test('the output directory is created when missing', () async {
    final package = await TempPackage.create('site', {
      'lib/main.client.dart': 'void main() {}',
    });

    await ClientBundler(
      package.root,
      outputDirectory: 'web/fresh',
      runner: FakeCompileRunner(files: ['{output}']),
    ).build(release: true);

    expect(package.dir.exists('web/fresh/main.client.dart.js'), isTrue);
  });

  test('the staging directory is removed after success and failure', () async {
    final package = await _package();

    for (final exitCode in [0, 1]) {
      await ClientBundler(
        package.root,
        runner: FakeCompileRunner(exitCode: exitCode),
      ).build(release: true);

      final staging = Directory(package.dir.resolve('.dart_tool/grund_bundle'));
      expect(staging.listSync(), isEmpty, reason: 'exit $exitCode');
    }
  });

  test('the output name follows the entry', () async {
    final package = await TempPackage.create('site');

    final bundler = ClientBundler(
      package.root,
      entry: 'lib/enhance/site.client.dart',
    );

    expect(bundler.outputName, 'site.client.dart.js');
  });

  test('release arguments are -O2 with the define and no source maps', () {
    expect(
      ProcessCompileRunner.arguments(
        entry: 'lib/main.client.dart',
        output: 'out.js',
        release: true,
      ),
      [
        'compile',
        'js',
        '-O2',
        '-Djaspr.flags.release=true',
        '--no-source-maps',
        '-o',
        'out.js',
        'lib/main.client.dart',
      ],
    );
  });

  test('development arguments are -O1 and keep the maps', () {
    final arguments = ProcessCompileRunner.arguments(
      entry: 'e.dart',
      output: 'out.js',
      release: false,
    );

    expect(arguments, ['compile', 'js', '-O1', '-o', 'out.js', 'e.dart']);
  });

  test('the process runner refuses an executable that is not dart', () {
    const runner = ProcessCompileRunner(executable: '/x/grund');

    expect(
      runner.compileJs(
        entry: 'lib/main.client.dart',
        output: '/tmp/out.js',
        release: true,
        workingDirectory: '/tmp',
      ),
      throwsA(
        isA<CliFailure>()
            .having((f) => f.exitCode, 'exitCode', CliExitCode.software)
            .having((f) => f.message, 'message', contains('AOT')),
      ),
    );
  });
}
