import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_generator/src/emit/import_allocator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture;

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<String> generated(String library) async {
    final result = const GrundGenerator.core().generate(
      await fixture.collect(['lib/public/$library.dart']),
    );
    expect(result.diagnostics, isEmpty);
    return result.files['lib/public/$library.g.dart']!;
  }

  test(
    'a declaration of another package is imported from its barrel',
    () async {
      final source = await generated('via_barrel');

      expect(
        source,
        contains("import 'package:other_pkg/other_pkg.dart' as i"),
      );
      expect(source, isNot(contains('package:other_pkg/src/')));
    },
  );

  test('the declaring file is imported when the host has no public '
      'library with the declaration', () async {
    final source = await generated('via_src');

    expect(
      source,
      contains("import 'package:other_pkg/src/other_module.dart' as i"),
    );
  });

  test('a barrel that hides the declaration is not used for it', () async {
    final source = await generated('via_hide');

    expect(
      source,
      contains("import 'package:other_pkg/src/other_module.dart' as i"),
    );
    expect(source, isNot(contains('package:other_pkg/other_pkg.dart')));
  });

  test('a barrel that shows the declaration is used for it', () async {
    final source = await generated('via_show');

    expect(source, contains("import 'package:other_pkg/other_pkg.dart' as i"));
    expect(source, isNot(contains('package:other_pkg/src/')));
  });

  test('the core barrel wins over a public library that exports a core '
      'declaration', () {
    final allocator = ImportAllocator(
      const PublicImports({
        'package:grund/src/module.dart#Module': 'package:other/other.dart',
      }),
    );

    expect(
      allocator.allocate(
        const Reference('Module', 'package:grund/src/module.dart'),
      ),
      'grund.Module',
    );
  });
}
