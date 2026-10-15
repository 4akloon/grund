import 'package:grund_build/grund_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/shop_sources.dart';

Future<BuildRun> _build(Map<String, String> files) =>
    BuildRun.run(GrundBuilder(ShopSources.package), ShopSources.package, files);

void main() {
  test('the library is the one the CLI writes', () async {
    final build = await _build(ShopSources.files);
    final cli = await CliGeneration.run(ShopSources.package, ShopSources.files);

    expect(build.succeeded, isTrue);
    expect(build.library, cli.library);
  });

  test('a package without annotations gets no library', () async {
    final build = await _build({
      'lib/src/plain.dart': 'final class Plain {}\n',
    });

    expect(build.succeeded, isTrue);
    expect(build.library, isNull);
  });

  // Review Focus 1: a stale or foreign *.grund.dart in lib/ is not read.
  test('generated libraries in lib/ are not sources', () async {
    final files = {
      ...ShopSources.files,
      'lib/src/old.grund.dart': 'this is not Dart',
    };

    final build = await _build(files);

    expect(build.succeeded, isTrue);
    expect(build.library, (await CliGeneration.run('shop', files)).library);
  });

  // Review Focus 4: build_runner may run before json_serializable.
  test('a part another builder has not written yet changes nothing', () async {
    final withPart = await _build({
      'lib/src/user.dart': ShopSources.user,
      'lib/src/user.g.dart': ShopSources.userPart,
      'lib/src/users.dart': ShopSources.users,
    });
    final withoutPart = await _build({
      'lib/src/user.dart': ShopSources.user,
      'lib/src/users.dart': ShopSources.users,
    });

    expect(withPart.library, isNotNull);
    expect(withoutPart.library, withPart.library);
  });
}
