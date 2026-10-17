import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/dart_diagnostics.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

void main() {
  test('init --template fullstack writes pages that analyze', () async {
    final dir = TempDir.create();
    final target = dir.resolve('my_site');

    final init = await CliRun.run(['init', '--template', 'fullstack', target]);
    await WorkspacePackageConfig.write(target, 'my_site');

    expect(init.exitCode, 0, reason: init.err);
    expect(init.out, contains('  lib/src/pages/home_page.dart\n'));
    expect(init.out, contains('  web/styles.css\n'));
    expect(init.out, endsWith('  dart pub get\n  dart run grund_cli dev\n'));
    final pubspec = dir.read('my_site/pubspec.yaml');
    expect(pubspec, contains('  grund_auth: ^0.2.0\n'));
    expect(pubspec, contains('  grund_cli: ^0.2.0\n'));
    expect(pubspec, contains('  grund_http: ^0.3.0\n'));
    expect(pubspec, contains('  grund_jaspr: ^0.3.0\n'));
    expect(pubspec, contains("  jaspr: '>=0.23.5 <0.24.0'\n"));
    expect(
      dir.read('my_site/lib/src/home_site_module.dart'),
      contains('Pages.under<PublicSite>'),
    );
    final module = dir.read('my_site/lib/src/app_module.dart');
    expect(module, contains('    EnvironmentModule(),\n'));
    expect(module, contains('HttpModule.fromEnvironment(use: ['));
    expect(await DartDiagnostics.of(target), isEmpty);
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
