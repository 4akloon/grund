// The builder and `grund_cli gen` over the same sources: the same file set,
// byte for byte, for the golden package users_app and for a small shop.
import 'package:grund_build/grund_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/fixture_files.dart';
import 'helpers/shop_sources.dart';

void main() {
  test('users_app: the builder writes the files the CLI writes', () async {
    final sources = await FixtureFiles.of('users_app');

    final build = await BuildRun.run(GrundBuilder(), 'users_app', sources);
    final cli = await CliGeneration.run('users_app', sources);

    expect(cli.files, hasLength(4));
    expect(build.outputs, cli.files);
  });

  test('users_app: the builder writes the committed golden files', () async {
    final sources = await FixtureFiles.of('users_app');
    final golden = await FixtureFiles.of('users_app', generated: true)
      ..removeWhere((path, _) => sources.containsKey(path));

    final build = await BuildRun.run(GrundBuilder(), 'users_app', sources);

    expect(build.outputs, golden);
  });

  test('shop: the builder writes the files the CLI writes', () async {
    final build = await BuildRun.run(
      GrundBuilder(),
      ShopSources.package,
      ShopSources.files,
    );
    final cli = await CliGeneration.run(ShopSources.package, ShopSources.files);

    expect(cli.files.keys, [ShopSources.moduleOutput, ShopSources.apiOutput]);
    expect(build.outputs, cli.files);
  });
}
