import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:grund_http_generator/src/construct/api_host_check.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _location = SourceLocation('lib/a.dart', 4, 7);

List<Diagnostic> _check({
  required bool hasPartDirective,
  required bool hasHttpImport,
}) => ApiHostCheck.check(
  HttpPackageModel(
    hosts: [
      ApiHost(
        path: 'lib/a.dart',
        location: _location,
        hasPartDirective: hasPartDirective,
        hasHttpImport: hasHttpImport,
      ),
    ],
  ),
).toList();

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('http_cases_app'));

  Future<List<Diagnostic>> diagnostics(String path) async {
    final package = await fixture.collect([path]);
    return const GrundGenerator(
      FixturePackage.constructs,
    ).generate(package).diagnostics;
  }

  test('a host with the part and the prefixed import is fine', () async {
    expect(await diagnostics('lib/apis/tasks.dart'), isEmpty);
  });

  test('a host without the part directive is reported with its fix', () async {
    final result = await diagnostics('lib/apis/no_part.dart');

    expect(
      [for (final d in result) d.code],
      [HttpDiagnosticCodes.missingPartDirective],
    );
    expect(result.single.location.path, 'lib/apis/no_part.dart');
    expect(result.single.location.line, 7);
    expect(result.single.message, contains("part 'no_part.g.dart';"));
  });

  test(
    'a host with only an unprefixed import lacks the prefixed one',
    () async {
      final result = await diagnostics('lib/apis/unhosted.dart');

      expect(
        [for (final d in result) d.code],
        [
          HttpDiagnosticCodes.missingPartDirective,
          HttpDiagnosticCodes.missingRequiredImport,
        ],
      );
      expect(
        result.last.message,
        contains("import 'package:grund_http/grund_http.dart' as http;"),
      );
    },
  );

  test('a host with the part but without the import is reported', () {
    final result = _check(hasPartDirective: true, hasHttpImport: false);

    expect(
      [for (final d in result) d.code],
      [HttpDiagnosticCodes.missingRequiredImport],
    );
    expect(result.single.location, _location);
  });

  test('a host with the import but without the part is reported', () {
    final result = _check(hasPartDirective: false, hasHttpImport: true);

    expect(
      [for (final d in result) d.code],
      [HttpDiagnosticCodes.missingPartDirective],
    );
  });

  test('a part directive of another directory does not count', () async {
    final result = await diagnostics('lib/apis/wrong_part.dart');

    expect(
      [for (final d in result) d.code],
      [HttpDiagnosticCodes.missingPartDirective],
    );
  });

  test('a part directive written with ./ still counts', () async {
    expect(await diagnostics('lib/apis/dotted_part.dart'), isEmpty);
  });

  test('an api declared in a part file is generated for its host', () async {
    final package = await fixture.collect(['lib/apis/in_part.dart']);
    final result = const GrundGenerator(
      FixturePackage.constructs,
    ).generate(package);

    expect(result.diagnostics, isEmpty);
    expect(result.files.keys, ['lib/apis/in_part.g.dart']);
    expect(
      package.extensionModel<HttpPackageModel>()?.hosts.single.path,
      'lib/apis/in_part.dart',
    );
  });
}
