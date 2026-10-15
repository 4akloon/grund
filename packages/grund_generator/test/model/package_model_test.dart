import 'package:grund_generator/grund_generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  test('a package without modules, injectables or apis is empty', () {
    expect(GraphModels.package([]).isEmpty, isTrue);
  });

  test('a module makes the package non-empty', () {
    expect(GraphModels.package([GraphModels.module('App')]).isEmpty, isFalse);
  });

  test('an injectable makes the package non-empty', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      injectables: [GraphModels.provider('Clock').injectable],
    );

    expect(package.isEmpty, isFalse);
  });

  test('a module lists the bindings of its providers and @Provides', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('Repo', needs: ['Clock']),
      ],
      provides: [GraphModels.provides('App', 'Clock')],
    );

    expect([for (final b in module.bindings) '${b.key}'], ['Repo', 'Clock']);
  });
}
