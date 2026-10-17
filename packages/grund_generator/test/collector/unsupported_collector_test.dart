import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/provides_model.dart';
import 'package:grund_generator/src/model/unsupported_use.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open('cases_app')
        .collect(['lib/unsupported.dart', 'lib/modules/basic.dart']);
  });

  InjectableModel injectable(String name) =>
      package.injectables.firstWhere((i) => i.type.name == name);

  ProvidesModel provides(String name) => package.modules
      .firstWhere((m) => m.type.name == 'ScopedModule')
      .provides
      .firstWhere((p) => p.methodName == name);

  List<UnsupportedUse> uses(String element) => [
    for (final use in package.unsupportedUses)
      if (use.element == element) use,
  ];

  group('scopes', () {
    test('an aliased scope is read by its value', () {
      expect(injectable('AliasedScope').lifetime, Lifetime.scoped);
      expect(injectable('AliasedScope').scopeProblem, isNull);
      expect(provides('aliased').lifetime, Lifetime.scoped);
      expect(provides('aliased').problem, isNull);
    });

    test('an unresolved @Injectable scope is a recorded problem', () {
      expect(injectable('UnresolvedScope').scopeProblem, contains('Scope'));
    });

    test('an unresolved @Provides scope is a recorded problem', () {
      expect(provides('unresolved').problem, contains('Scope'));
      expect(provides('unresolved').key, isNull);
    });

    test('an annotation that does not evaluate is an unsupported use', () {
      expect(uses('BrokenAnnotation').single.reason, contains('@Injectable'));
    });
  });

  group('provides return types', () {
    test('a Future of a Future is rejected', () {
      expect(provides('nested').problem, contains('must return'));
    });

    test('a nullable Future is rejected', () {
      expect(provides('nullable').problem, contains('must return'));
    });
  });

  test('a Bind implementation keeps its @Named', () {
    final bind = package.modules
        .firstWhere((m) => m.type.name == 'ScopedModule')
        .providers
        .firstWhere((p) => p.injectable.type.name == 'NamedClock');

    expect("${bind.key}", "Clock('custom')");
  });

  group('inherited and misplaced annotations', () {
    test('an inherited @Provides is recorded', () {
      expect(uses('InheritingModule').single.reason, contains('Base.tx'));
    });

    test('@Injectable on a mixin is recorded', () {
      expect(uses('AnnotatedMixin').single.reason, contains('@Injectable'));
    });

    test('@Injectable on an enum is recorded', () {
      expect(uses('AnnotatedEnum').single.reason, contains('@Injectable'));
      expect(
        uses('AnnotatedEnum').single.location.path,
        'lib/unsupported.dart',
      );
    });
  });
}
