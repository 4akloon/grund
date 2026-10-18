import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/fake_compile_runner.dart';
import 'helpers/temp_package.dart';

void main() {
  test('without the entry bundle says so and exits with 0', () async {
    final package = await TempPackage.create('site');

    final run = await CliRun.run(['bundle', '-C', package.dir.path]);

    expect(run.exitCode, 0);
    expect(run.out, 'No lib/main.client.dart: nothing to bundle.\n');
  });

  test('help lists --entry and --output but no --release', () async {
    final run = await CliRun.run(['bundle', '--help']);

    expect(run.out, contains('--entry'));
    expect(run.out, contains('--output'));
    expect(run.out, isNot(contains('--release')));
  });

  test('bundle compiles in production mode and reports the file', () async {
    final package = await TempPackage.create('site', {
      'lib/main.client.dart': 'void main() {}',
    });
    final runner = FakeCompileRunner();

    final run = await CliRun.run([
      'bundle',
      '-C',
      package.dir.path,
    ], compileRunner: runner);

    expect(run.exitCode, 0);
    expect(
      run.out,
      matches(
        RegExp(r'^Bundled web/client/main\.client\.dart\.js in \d+ ms\.\n$'),
      ),
    );
    expect(runner.releases, [true]);
  });

  test('--entry bundles that file and removes only its own files', () async {
    final package = await TempPackage.create('site', {
      'lib/enhance/site.client.dart': 'void main() {}',
      'web/enhance/site.client.dart.js': 'old',
      'web/enhance/site.client.dart.js.gz': 'old',
      'web/enhance/other.client.dart.js': 'other',
    });
    final runner = FakeCompileRunner();

    final run = await CliRun.run([
      'bundle',
      '--entry',
      'lib/enhance/site.client.dart',
      '--output',
      'web/enhance',
      '-C',
      package.dir.path,
    ], compileRunner: runner);

    expect(run.exitCode, 0);
    expect(runner.entries, ['lib/enhance/site.client.dart']);
    expect(package.dir.read('web/enhance/site.client.dart.js'), 'new');
    expect(package.dir.exists('web/enhance/site.client.dart.js.gz'), isFalse);
    expect(package.dir.read('web/enhance/other.client.dart.js'), 'other');
    expect(package.dir.exists('web/enhance/site.client.dart.js.deps'), isFalse);
  });

  test('a failed compilation exits with 1 and prints the output', () async {
    final package = await TempPackage.create('site', {
      'lib/main.client.dart': 'void main() {}',
    });

    final run = await CliRun.run([
      'bundle',
      '-C',
      package.dir.path,
    ], compileRunner: FakeCompileRunner(exitCode: 1));

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.err, 'bundle failed:\nError: broken\n');
  });
}
