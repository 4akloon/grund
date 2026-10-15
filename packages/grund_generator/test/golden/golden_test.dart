// The generated library of users_app, compared with the committed one.
// Regenerate it with: GRUND_UPDATE_GOLDENS=1 dart test test/golden
import 'dart:io';

import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _golden = 'lib/users_app.grund.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('users_app'));

  test('users_app generates its committed library', () async {
    final result = const GrundGenerator.core().generate(
      await fixture.collect(),
    );

    expect(result.diagnostics, isEmpty);
    final library = result.library ?? fail('no library');
    if (Platform.environment['GRUND_UPDATE_GOLDENS'] == '1') {
      File(p.join(fixture.root, _golden)).writeAsStringSync(library);
    }
    expect(library, fixture.read(_golden));
  });

  // Review Focus 2: drivers pass libraries in any order.
  test('the output does not depend on the order of libraries', () async {
    final libraries = await fixture.libraries();
    final collector = PackageCollector('users_app', fixture.root);

    final forward = const GrundGenerator.core().generate(
      collector.collect(libraries),
    );
    final backward = const GrundGenerator.core().generate(
      collector.collect(libraries.reversed),
    );

    expect(backward.library, forward.library);
  });

  test('the model carries documentation and data classes', () async {
    final package = await fixture.collect();

    expect(
      package.modules.firstWhere((m) => m.id == 'config').documentation,
      '/// Configuration every module sees.',
    );
    expect(
      [for (final dto in package.dtos) dto.type.name],
      ['CreateUserDto', 'User'],
    );
  });
}
