import 'package:grund_generator/src/model/dependency_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/providers/constructors.dart', 'lib/modules/basic.dart']);
  });

  InjectableModel injectable(String name) =>
      package.injectables.firstWhere((i) => i.type.name == name);

  List<String> dependencies(String name) => [
    for (final dependency in injectable(name).constructor.dependencies)
      switch (dependency) {
        DependencyModel(:final key?) => '${dependency.name}: $key',
        DependencyModel(:final problem) => '${dependency.name}: $problem',
      },
  ];

  test('injectables keep their scope and name', () {
    expect(injectable('Tx').lifetime, Lifetime.scoped);
    expect(injectable('Fine').lifetime, Lifetime.transient);
    expect(injectable('SystemClock').lifetime, Lifetime.singleton);
    expect("${injectable('PrimaryDb').key}", "PrimaryDb('primary')");
  });

  test('dependencies by type, by name and by required name', () {
    expect(dependencies('Repo'), [
      'clock: Clock',
      "db: PrimaryDb('primary')",
      'config: AppConfig',
    ]);
    expect(injectable('Repo').constructor.dependencies.last.isNamed, isTrue);
    expect(dependencies('Fine'), [
      'clock: Clock',
      "db: PrimaryDb('primary')",
      'repo: Repo',
    ]);
  });

  test('classes dependency injection cannot create', () {
    expect(injectable('Shape').constructor.problem, 'Shape is abstract.');
    expect(
      injectable('Box').constructor.problem,
      'Box is generic; provide a subclass with fixed type arguments.',
    );
    expect(
      injectable('OnlyNamed').constructor.problem,
      'OnlyNamed has no unnamed constructor; grund creates it with '
      'OnlyNamed(...).',
    );
    expect(injectable('_Hidden').constructor.problem, '_Hidden is private.');
  });

  test('an abstract class with a factory can be created', () {
    expect(injectable('Service').constructor.problem, isNull);
  });

  test('parameters dependency injection cannot fill', () {
    expect(dependencies('Optional'), [
      'clock: Parameter clock of Optional is optional; grund injects '
          'required positional and required named parameters only.',
    ]);
    expect(dependencies('Odd'), [
      'clock: Parameter clock of Odd has type Clock?; grund injects '
          'non-nullable class types, qualified with @Named.',
      'callback: Parameter callback of Odd has type void Function(); grund '
          'injects non-nullable class types, qualified with @Named.',
    ]);
    expect(dependencies('Loose'), [
      'anything: Parameter anything of Loose has type Object; grund injects '
          'non-nullable class types, qualified with @Named.',
    ]);
  });

  test('a @Provides method of a class that is no module is stray', () {
    expect(
      [for (final s in package.strayProvides) '${s.owner}.${s.methodName}'],
      ['NotAModule.plain'],
    );
  });
}
