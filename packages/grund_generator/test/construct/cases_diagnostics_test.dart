import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// The diagnostics of the invalid libraries of `cases_app`, with their exact
/// position: a user finds the problem by `path:line:col`.
void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<List<String>> problems(List<String> paths) async {
    final package = await fixture.collect(paths);
    return [
      for (final d in const GrundGenerator.core().generate(package).diagnostics)
        '${d.location} ${d.code.id}',
    ];
  }

  test('the broken modules and providers are found where they are', () async {
    expect(
      await problems([
        'lib/modules/invalid_entries.dart',
        'lib/modules/basic.dart',
      ]),
      [
        'lib/modules/basic.dart:75:26 invalid_provides',
        'lib/modules/basic.dart:79:8 invalid_provides',
        'lib/modules/basic.dart:83:15 invalid_provides',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_class',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:13:7 invalid_module_entry',
      ],
    );
  });

  test(
    'the valid libraries of cases_app generate without a diagnostic',
    () async {
      expect(await problems(['lib/emit/modules.dart']), isEmpty);
    },
  );
}
