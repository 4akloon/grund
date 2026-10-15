import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';
import '../helpers/golden_files.dart';

/// `GRUND_UPDATE_GOLDENS=1 dart test test/golden` rewrites the golden set
/// after a deliberate change of the generated output.
void main() {
  late FixturePackage fixture; // Set in setUpAll.
  late GenerationResult result; // Set in setUpAll.

  Future<GenerationResult> generate(FixturePackage from) async =>
      const GrundGenerator(
        FixturePackage.constructs,
      ).generate(await from.collect());

  setUpAll(() async {
    fixture = FixturePackage.open('users_app');
    result = await generate(fixture);
    if (GoldenFiles.updateRequested) {
      if (result.diagnostics.isNotEmpty) {
        fail(
          'GRUND_UPDATE_GOLDENS=1 but users_app has diagnostics, nothing '
          'was written:\n${result.diagnostics.join('\n')}',
        );
      }
      GoldenFiles(fixture.root).write(result.files);
    }
  });

  test('users_app has no diagnostics', () {
    expect(result.diagnostics, isEmpty);
  });

  test('the generated set has the committed paths and bytes', () {
    final committed = GoldenFiles(fixture.root).read();

    expect(result.files.keys.toList()..sort(), committed.keys.toList()..sort());
    for (final MapEntry(key: path, value: content) in result.files.entries) {
      expect(content, committed[path], reason: path);
    }
  });

  test('generating from a fresh analysis gives the same bytes', () async {
    final again = await generate(FixturePackage.open('users_app'));

    expect(again.files, result.files);
  });

  test('an @Api and a @Module in one library get a part and a module file', () {
    expect(
      result.files.keys,
      containsAll(['lib/src/users_api.g.dart', 'lib/src/users_module.g.dart']),
    );
    expect(
      result.files['lib/src/users_module.g.dart'],
      contains('grund.Singleton<i2.UsersApiRoutes>('),
    );
  });
}
