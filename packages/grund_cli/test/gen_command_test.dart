import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_dir.dart';
import 'helpers/temp_package.dart';

Future<CliRun> _gen(TempPackage package) =>
    CliRun.run(['gen', '--directory', package.dir.path]);

void main() {
  test('gen writes the files and exits with 0', () async {
    final package = await TempPackage.create('shop', ShopSources.files);

    final first = await _gen(package);
    final second = await _gen(package);

    expect(first.exitCode, CliExitCode.success.code);
    expect(first.out, matches(RegExp(r'^Generated 2 files in \d+ ms\.\n$')));
    for (final output in ShopSources.outputs) {
      expect(package.dir.exists(output), isTrue);
    }
    expect(second.exitCode, 0);
    expect(
      second.out,
      matches(RegExp(r'^Generated files are up to date \(2 files, \d+ ms\)')),
    );
  });

  test('diagnostics are printed one per line and exit with 1', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/app_module.dart': ShopSources.moduleWithoutClock,
    });

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.out, isEmpty);
    final lines = run.err.trimRight().split('\n');
    expect(lines, hasLength(2));
    expect(
      lines.first,
      allOf(
        startsWith('lib/src/time_api.dart:'),
        contains('Clock'),
        endsWith('[missing_provider]'),
      ),
    );
    expect(lines.last, '1 problem; no generated file was changed.');
    for (final output in ShopSources.outputs) {
      expect(package.dir.exists(output), isFalse);
    }
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
    Directory(package.dir.resolve(ShopSources.moduleOutput)).createSync();

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.cannotCreate.code);
    expect(run.err, startsWith('Cannot write ${ShopSources.moduleOutput}: '));
  });

  // Review Focus 9: every way the command line can be wrong.
  test('a wrong command line exits with 64 and prints usage', () async {
    final unknown = await CliRun.run(['generate']);
    final option = await CliRun.run(['gen', '--fast']);
    final positional = await CliRun.run(['gen', 'lib']);

    for (final run in [unknown, option, positional]) {
      expect(run.exitCode, CliExitCode.usage.code);
      expect(run.out, isEmpty);
      expect(run.err, contains('Usage: grund '));
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
