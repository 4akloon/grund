import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_dir.dart';
import 'helpers/temp_package.dart';

Future<CliRun> _gen(TempPackage package) =>
    CliRun.run(['gen', '--directory', package.dir.path]);

void main() {
  test('gen writes the library and exits with 0', () async {
    final package = await TempPackage.create('shop', ShopSources.files);

    final first = await _gen(package);
    final second = await _gen(package);

    expect(first.exitCode, CliExitCode.success.code);
    expect(
      first.out,
      matches(RegExp(r'^Generated lib/shop\.dartnest\.dart in \d+ ms\.\n$')),
    );
    expect(package.dir.exists(ShopSources.output), isTrue);
    expect(second.exitCode, 0);
    expect(second.out, contains('lib/shop.dartnest.dart is up to date'));
  });

  test('diagnostics are printed one per line and exit with 1', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/app_module.dart': ShopSources.moduleWithoutClock,
    });

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.out, isEmpty);
    expect(
      run.err,
      'lib/src/time_controller.dart:7:23: error: No provider for Clock in '
      'module "app" (resolving: TimeController). [missing_provider]\n'
      '1 problem; lib/shop.dartnest.dart was not changed.\n',
    );
    expect(package.dir.exists(ShopSources.output), isFalse);
  });

  test('a syntax error is a problem too', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/clock.dart': 'final class Clock {',
    });

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.err, startsWith('lib/src/clock.dart:1:'));
    expect(run.err, contains('[syntax_error]'));
  });

  test('a package without annotations has nothing to generate', () async {
    final package = await TempPackage.create('shop', {
      'lib/shop.dart': 'int answer() => 42;\n',
    });

    final run = await _gen(package);

    expect(run.exitCode, 0);
    expect(run.out, 'No annotations in lib/; nothing to generate.\n');
  });

  test('a directory without a package exits with 66', () async {
    final dir = TempDir.create();

    final run = await CliRun.run(['gen', '-C', dir.path]);

    expect(run.exitCode, CliExitCode.noInput.code);
    expect(run.err, startsWith('No pubspec.yaml in ${dir.path}'));
  });

  test('an output that cannot be written exits with 73', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    Directory(package.dir.resolve(ShopSources.output)).createSync();

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.cannotCreate.code);
    expect(run.err, startsWith('Cannot write lib/shop.dartnest.dart: '));
  });

  // Review Focus 9: every way the command line can be wrong.
  test('a wrong command line exits with 64 and prints usage', () async {
    final unknown = await CliRun.run(['generate']);
    final option = await CliRun.run(['gen', '--fast']);
    final positional = await CliRun.run(['gen', 'lib']);

    for (final run in [unknown, option, positional]) {
      expect(run.exitCode, CliExitCode.usage.code);
      expect(run.out, isEmpty);
      expect(run.err, contains('Usage: dartnest_cli'));
    }
    expect(positional.err, startsWith('gen takes no positional arguments.'));
  });

  test('help goes to stdout and exits with 0', () async {
    final top = await CliRun.run(['--help']);
    final gen = await CliRun.run(['gen', '--help']);

    expect(top.exitCode, 0);
    expect(top.out, contains('gen'));
    expect(gen.exitCode, 0);
    expect(gen.out, contains('--directory'));
  });
}
