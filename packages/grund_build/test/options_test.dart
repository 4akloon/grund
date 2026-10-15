import 'package:build/build.dart';
import 'package:grund_build/grund_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/shop_sources.dart';

Future<BuildRun> _build(Map<String, Object?> config) => BuildRun.run(
  grundBuilder(BuilderOptions(config)),
  ShopSources.package,
  ShopSources.files,
);

String _error(String problem) =>
    'grund_build cannot build shop: $problem. '
    'Name the package in its build.yaml:\n\n'
    'targets:\n'
    '  \$default:\n'
    '    builders:\n'
    '      grund_build:\n'
    '        options:\n'
    '          package: shop\n';

void main() {
  test('the package option names the library', () async {
    final builder = grundBuilder(const BuilderOptions({'package': 'shop'}));

    expect(builder.buildExtensions, {
      r'$lib$': ['shop.grund.dart'],
    });
    expect(
      grundBuilder(const BuilderOptions({})).buildExtensions[r'$lib$'],
      isNotEmpty,
    );
    expect((await _build({'package': 'shop'})).library, isNotNull);
  });

  test('a missing package option fails the build', () async {
    final build = await _build({});

    expect(build.succeeded, isFalse);
    expect(build.errors, [_error('the option "package" is missing')]);
    expect(build.library, isNull);
  });

  test('an invalid package name fails the build', () async {
    final build = await _build({'package': 'Shop-App'});

    expect(build.errors, [_error('"Shop-App" is not a package name')]);
  });

  test('a package option that is not a string fails the build', () async {
    final build = await _build({'package': 5});

    expect(build.errors, [_error('"5" is not a package name')]);
  });

  test('an unknown option fails the build', () async {
    final build = await _build({'package': 'shop', 'pakage': 'shop'});

    expect(build.errors, [_error('unknown option pakage')]);
  });

  // Review Focus 2: build.yaml copied from another workspace member.
  test('the name of another package fails the build', () async {
    final build = await _build({'package': 'users_app'});

    expect(build.succeeded, isFalse);
    expect(build.errors, [
      'grund_build cannot build shop: its build.yaml names the package '
          '"users_app". Name the package in its build.yaml:\n\n'
          '${GrundBuildOptions.buildYaml('shop')}',
    ]);
    expect(build.library, isNull);
  });
}
