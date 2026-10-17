import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  const library = 'lib/providers/primary_constructors.dart';
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open('cases_app').collect([library]);
  });

  List<String> dependencies(String name) => [
    for (final dependency
        in package.injectables
            .firstWhere((i) => i.type.name == name)
            .constructor
            .dependencies)
      '${dependency.name}: ${dependency.key}',
  ];

  test('a primary constructor declares the dependencies of an injectable', () {
    expect(dependencies('PrimaryConstructorRepo'), [
      '_db: PrimaryConstructorDb',
    ]);
  });

  test('a private named parameter is injected by its public name', () {
    expect(dependencies('PrivateNamedGreeter'), [
      'repo: PrimaryConstructorRepo',
    ]);
  });

  test('the classes generate into a module without a diagnostic', () {
    final result = const GrundGenerator.core().generate(package);

    expect(result.diagnostics, isEmpty);
    expect(
      result.files['lib/providers/primary_constructors.g.dart'],
      allOf(
        contains('i1.PrimaryConstructorRepo(i<i1.PrimaryConstructorDb>())'),
        contains(
          'i1.PrivateNamedGreeter(repo: i<i1.PrimaryConstructorRepo>())',
        ),
      ),
    );
  });
}
