// The builder and `dartnest_cli gen` over the generator's fixtures: the same
// bytes for users_app (the golden package), the same problems for
// cases_app (one scenario per library, most of them invalid).
import 'dart:convert';

import 'package:dartnest_build/dartnest_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/fixture_files.dart';

void main() {
  test('users_app: the builder writes the bytes the CLI writes', () async {
    final build = await BuildRun.run(DartnestBuilder('users_app'), 'users_app');
    final cli = await CliGeneration.run(
      'users_app',
      await FixtureFiles.of('users_app'),
    );

    final library = cli.library ?? fail('the CLI wrote no library');
    expect(utf8.encode(build.library ?? ''), utf8.encode(library));
  });

  test('users_app: the builder writes the committed golden library', () async {
    final build = await BuildRun.run(DartnestBuilder('users_app'), 'users_app');
    final golden = await FixtureFiles.golden('users_app');

    expect(build.library, golden);
  });

  test('cases_app: the builder reports the problems the CLI reports', () async {
    final build = await BuildRun.run(DartnestBuilder('cases_app'), 'cases_app');
    final cli = await CliGeneration.run(
      'cases_app',
      await FixtureFiles.of('cases_app'),
    );

    expect(cli.report.diagnostics, isNotEmpty);
    expect(build.errors, cli.report.problemLines);
  });
}
