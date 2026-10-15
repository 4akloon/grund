import 'dart:io';

import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _committed = 'test/fixtures/http_cases_app/lib/apis/async_results.g.dart';

/// A handler declared `FutureOr<...>` is awaited like one declared `Future`.
void main() {
  late String generated; // Set in setUpAll.
  late List<Diagnostic> diagnostics; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('http_cases_app');
    final result = const GrundGenerator(
      FixturePackage.constructs,
    ).generate(await fixture.collect(['lib/apis/async_results.dart']));
    diagnostics = result.diagnostics;
    generated = result.files['lib/apis/async_results.g.dart'] ?? '';
  });

  test('a FutureOr<void> handler is awaited before the 204', () {
    expect(diagnostics, isEmpty);
    expect(generated, contains("await _api.remove(c.path.integer('id'))"));
    expect(generated, contains('await _api.boom()'));
  });

  test('the committed part is what the generator writes', () {
    if (Platform.environment['GRUND_UPDATE_GOLDENS'] == '1') {
      File(_committed).writeAsStringSync(generated);
    }
    expect(File(_committed).readAsStringSync(), generated);
  });
}
