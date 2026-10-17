import 'dart:io';

import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _committed = 'test/fixtures/http_cases_app/lib/apis/suffix_route.g.dart';

/// Routes with a literal suffix on their last parameter generate cleanly.
void main() {
  late String generated; // Set in setUpAll.
  late List<Diagnostic> diagnostics; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('http_cases_app');
    final result = const GrundGenerator(FixturePackage.constructs)
        .generate(await fixture.collect(['lib/apis/suffix_route.dart']));
    diagnostics = result.diagnostics;
    generated = result.files['lib/apis/suffix_route.g.dart'] ?? '';
  });

  test('suffixed and plain parameter routes are not in conflict', () {
    expect(diagnostics, isEmpty);
    expect(generated, contains("'/:id.json'"));
    expect(generated, contains("'/:id'"));
  });

  test('the committed part is what the generator writes', () {
    if (Platform.environment['GRUND_UPDATE_GOLDENS'] == '1') {
      File(_committed).writeAsStringSync(generated);
    }
    expect(File(_committed).readAsStringSync(), generated);
  });
}
