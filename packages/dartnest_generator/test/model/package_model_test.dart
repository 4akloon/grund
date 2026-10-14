import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  test('a package without modules, injectables or controllers is empty', () {
    expect(GraphModels.package([]).isEmpty, isTrue);
  });

  test('a module makes the package non-empty', () {
    expect(GraphModels.package([GraphModels.module('App')]).isEmpty, isFalse);
  });

  test('a controller makes the package non-empty', () {
    final controller = GraphModels.controller('Users', guard: 'Auth');

    expect(GraphModels.package([], [controller]).isEmpty, isFalse);
  });

  test('an injectable makes the package non-empty', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      injectables: [
        InjectableModel(
          type: GraphModels.type('Clock'),
          isAnnotated: true,
          constructor: const ConstructorModel([]),
          location: const SourceLocation('lib/app.dart', 1, 7),
        ),
      ],
    );

    expect(package.isEmpty, isFalse);
  });
}
