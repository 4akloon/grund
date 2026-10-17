import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/construct/generation_result.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// `Environment` comes from `EnvironmentModule` of package `grund`, so a
/// module that reads it imports the module itself (docs/configuration.md).
void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<GenerationResult> generate(String path) async =>
      const GrundGenerator.core().generate(await fixture.collect([path]));

  test(
    'modules importing EnvironmentModule themselves generate cleanly',
    () async {
      final result = await generate('lib/modules/environment_import.dart');

      expect(result.diagnostics, isEmpty);
      expect(result.isSuccess, isTrue);
    },
  );

  test(
    'a module reading Environment without the import is missing_provider',
    () async {
      final result = await generate('lib/modules/environment_missing.dart');

      expect(result.diagnostics.map((d) => d.code.id), ['missing_provider']);
    },
  );
}
