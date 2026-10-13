import 'package:dartnest_generator/src/collector/package_collector.dart';
import 'package:dartnest_generator/src/model/module_model.dart';
import 'package:dartnest_generator/src/model/module_reference.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/provider_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<ModuleModel> moduleOf(String path, String name) async {
    final package = await fixture.collect([path]);
    return package.modules.firstWhere((m) => m.type.name == name);
  }

  test('only references to usable function tear-offs are kept', () async {
    final module = await moduleOf(
      'lib/modules/references.dart',
      'ReferencesModule',
    );

    expect(
      [for (final reference in module.imports) reference.display],
      ['ModuleFactories.create', 'optionalArgument'],
    );
    final create = module.imports.first as OpaqueModuleReference;
    expect(create.enclosingName, 'ModuleFactories');
    expect(create.libraryUri, 'package:cases_app/modules/references.dart');
    expect(module.invalidEntries, [
      'imports: withArgument is not a module.',
      'imports: _hidden is not a module.',
      'imports: needsArgument is not a module.',
      'imports: notAModule is not a module.',
    ]);
  });

  test('a module of another package is a reference by naming rule', () async {
    final libraries = await fixture.libraries([
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);

    final package = PackageCollector(
      'consumer',
      fixture.root,
    ).collect(libraries);

    final app = package.modules.firstWhere((m) => m.type.name == 'AppModule');
    final db = app.imports.first as OpaqueModuleReference;
    expect(db.name, 'dbModule');
    expect(db.libraryUri, 'package:cases_app/cases_app.dartnest.dart');
    expect(db.enclosingName, isNull);
  });

  test('provider entries of the wrong shape', () async {
    final module = await moduleOf(
      'lib/modules/invalid_providers.dart',
      'OddProvidersModule',
    );

    expect(module.id, 'odd');
    expect(module.invalidEntries, [
      'providers: Bind<void Function(), void Function()> must bind a class '
          'to a class.',
      'providers: the value of Value(...) is not an object.',
      'providers: the token of Value(...) is not a Token.',
    ]);
    final enumeration = module.providers.first as ClassProvider;
    expect(enumeration.injectable.constructor.problem, 'Mode is not a class.');
    expect(module.providers.last, isA<ValueProvider>());
    expect(module.providers, hasLength(2));
  });

  test('a controller of this package is kept as a type', () async {
    final module = await moduleOf(
      'lib/modules/with_controller.dart',
      'PingModule',
    );

    expect([for (final c in module.controllers) c.name], ['PingController']);
    expect(module.invalidEntries, isEmpty);
  });

  test('constructors of private, factory and Object-typed classes', () async {
    final package = await fixture.collect(['lib/providers/constructors.dart']);
    final constructors = {
      for (final i in package.injectables) i.type.name: i.constructor,
    };

    expect(constructors['_Hidden']!.problem, '_Hidden is private.');
    expect(constructors['Service']!.problem, isNull);
    expect(constructors['Service']!.dependencies, isEmpty);
    expect(
      constructors['Loose']!.dependencies.single.problem,
      'Parameter anything of Loose has type Object; dartnest injects '
      'non-nullable class types, or a Token with @Inject(token).',
    );
  });

  test(
    'generated libraries are skipped and an empty input has a version',
    () async {
      final skipped = await fixture.collect(['lib/generated.dartnest.dart']);
      final empty = PackageCollector(
        'cases_app',
        fixture.root,
      ).collect(const []);

      expect(skipped.injectables, isEmpty);
      expect(skipped.languageVersion, empty.languageVersion);
      expect('${empty.languageVersion}', '3.8.0');
      expect(empty, isA<PackageModel>());
    },
  );
}
