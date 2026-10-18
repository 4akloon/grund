import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/dart_diagnostics.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

/// `init --template fullstack` into `my_site`, resolved against the
/// workspace so the package can be analyzed without `pub get`.
Future<({TempDir dir, String target, CliRun run})> _scaffold() async {
  final dir = TempDir.create();
  final target = dir.resolve('my_site');
  final run = await CliRun.run(['init', '--template', 'fullstack', target]);
  expect(run.exitCode, 0, reason: run.err);
  await WorkspacePackageConfig.write(target, 'my_site');
  return (dir: dir, target: target, run: run);
}

void main() {
  test('init --template fullstack writes pages that analyze', () async {
    final scaffold = await _scaffold();

    expect(await DartDiagnostics.of(scaffold.target), isEmpty);
  });

  test('the printed file list is sorted by path', () async {
    final scaffold = await _scaffold();

    final listed = RegExp(
      r'^  ((?:[\w.]+/)*[\w.]+)$',
      multiLine: true,
    ).allMatches(scaffold.run.out.split('Next').first);
    final paths = [for (final match in listed) match.group(1)!];

    expect(paths, hasLength(greaterThan(10)));
    expect(paths, [...paths]..sort());
  });

  test('the next steps end with the production bundle', () async {
    final scaffold = await _scaffold();

    expect(
      scaffold.run.out,
      endsWith(
        '  dart pub get\n'
        '  dart run grund_cli dev\n'
        '  dart run grund_cli bundle  # production bundle (-O2) for /static/client/\n',
      ),
    );
  });

  test('the client files are listed', () async {
    final scaffold = await _scaffold();

    for (final file in [
      'clients.dart',
      'main.client.dart',
      'src/pages/counter.dart',
    ]) {
      expect(scaffold.run.out, contains('  lib/$file\n'));
    }
  });

  test('the client bundle is ignored by git', () async {
    final scaffold = await _scaffold();

    expect(scaffold.dir.read('my_site/.gitignore'), contains('web/client/\n'));
  });

  test('the module and the home page use the counter island', () async {
    final scaffold = await _scaffold();

    expect(
      scaffold.dir.read('my_site/lib/src/app_module.dart'),
      contains('JasprModule(config: JasprConfig(clients: clients))'),
    );
    expect(
      scaffold.dir.read('my_site/lib/src/pages/home_page.dart'),
      contains('const Counter('),
    );
  });

  test('the pubspec pins the released packages', () async {
    final scaffold = await _scaffold();

    final pubspec = scaffold.dir.read('my_site/pubspec.yaml');
    expect(pubspec, contains('  grund_auth: ^0.2.0\n'));
    expect(pubspec, contains('  grund_cli: ^0.2.1\n'));
    expect(pubspec, contains('  grund_http: ^0.3.0\n'));
    expect(pubspec, contains('  grund_jaspr: ^0.3.1\n'));
    expect(pubspec, contains("  jaspr: '>=0.23.5 <0.24.0'\n"));
  });

  test('the site module declares its pages under PublicSite', () async {
    final scaffold = await _scaffold();

    expect(
      scaffold.dir.read('my_site/lib/src/home_site_module.dart'),
      contains('Pages.under<PublicSite>'),
    );
  });

  test('the app module wires the environment and the HTTP module', () async {
    final scaffold = await _scaffold();

    final module = scaffold.dir.read('my_site/lib/src/app_module.dart');
    expect(module, contains('    EnvironmentModule(),\n'));
    expect(module, contains('HttpModule.fromEnvironment(use: ['));
  });

  test(
    'the fullstack session cookie is Secure only in a product build',
    () async {
      final dir = TempDir.create();

      await CliRun.run(['init', '--template', 'fullstack', dir.resolve('s')]);

      final module = dir.read('s/lib/src/app_module.dart');
      expect(module, contains("bool.fromEnvironment('dart.vm.product')"));
      expect(module, contains('SessionConfig(secure: _isProduct)'));
    },
  );

  test('init without --template still writes the annotated API', () async {
    final dir = TempDir.create();

    final run = await CliRun.run(['init', dir.resolve('my_app')]);

    expect(run.exitCode, 0, reason: run.err);
    expect(dir.exists('my_app/lib/src/hello.dart'), isTrue);
    expect(dir.exists('my_app/web/styles.css'), isFalse);
  });

  test(
    'init --template fullstack rejects the name of a package it adds',
    () async {
      final dir = TempDir.create();

      final run = await CliRun.run([
        'init',
        '--template',
        'fullstack',
        dir.resolve('jaspr'),
      ]);

      expect(run.exitCode, CliExitCode.usage.code);
      expect(run.err, contains('a dependency of the new package'));
      expect(dir.exists('jaspr'), isFalse);
    },
  );

  test('init refuses a template it does not know', () async {
    final dir = TempDir.create();

    final run = await CliRun.run([
      'init',
      '--template',
      'mobile',
      dir.resolve('my_app'),
    ]);

    expect(run.exitCode, CliExitCode.usage.code);
    expect(run.err, contains('"mobile" is not an allowed value'));
    expect(dir.exists('my_app'), isFalse);
  });

  test('the help of init names every template', () async {
    final run = await CliRun.run(['init', '--help']);

    expect(run.out, contains('[api] (default)'));
    expect(run.out, contains('A JSON API written with annotations.'));
    expect(run.out, contains('[fullstack]'));
    expect(
      run.out,
      contains('Server-rendered Jaspr pages with cookie sessions.'),
    );
  });
}
