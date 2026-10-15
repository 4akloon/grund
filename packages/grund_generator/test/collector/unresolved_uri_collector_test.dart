import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<PackageModel> collect(String path) => fixture.collect([path]);

  test('a mistyped import is recorded at its directive', () async {
    final package = await collect('lib/uris/unresolved_import.dart');

    final uri = package.unresolvedUris.single;
    expect(uri.uri, 'package:grund/annotationz.dart');
    expect(uri.directive, 'import');
    expect(uri.location.path, 'lib/uris/unresolved_import.dart');
    expect(uri.location.line, 4);
    expect(uri.location.column, 1);
  });

  test('the generator reports it as unresolved_uri', () async {
    final package = await collect('lib/uris/unresolved_import.dart');

    final result = const GrundGenerator.core().generate(package);

    expect(
      result.diagnostics.map((d) => d.code),
      contains(DiagnosticCode.unresolvedUri),
    );
    expect(result.isSuccess, isFalse);
  });

  test('an import or part of a not yet generated file is no problem', () async {
    final package = await collect('lib/uris/fresh_checkout.dart');

    expect(package.unresolvedUris, isEmpty);
  });
}
