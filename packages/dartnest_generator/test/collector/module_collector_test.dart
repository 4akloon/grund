import 'package:dartnest_generator/src/collector/package_collector.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/dependency_model.dart';
import 'package:dartnest_generator/src/model/injectable_model.dart';
import 'package:dartnest_generator/src/model/module_export.dart';
import 'package:dartnest_generator/src/model/module_model.dart';
import 'package:dartnest_generator/src/model/module_reference.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/provider_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final libraries = await fixture.libraries([
      'lib/providers/constructors.dart',
      'lib/modules/invalid_entries.dart',
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);
    package = PackageCollector('cases_app', fixture.root).collect(libraries);
  });

  ModuleModel module(String name) =>
      package.modules.firstWhere((m) => m.type.name == name);

  InjectableModel injectable(String name) =>
      package.injectables.firstWhere((i) => i.type.name == name);

  List<String> dependencies(String name) => [
    for (final dependency in injectable(name).constructor.dependencies)
      switch (dependency) {
        DependencyModel(:final key?) => '${dependency.name}: $key',
        DependencyModel(:final problem) => '${dependency.name}: $problem',
      },
  ];

  test('modules and injectables in library URI order', () {
    expect(package.languageVersion.toString(), '3.8.0');
    expect(
      [for (final m in package.modules) m.type.name],
      ['AppModule', 'DbModule', 'BrokenModule'],
    );
    expect(package.injectables.first.type.name, 'SystemClock');
    expect(package.injectables.last.type.name, 'Fine');
  });

  test('a module keeps its id, flags, location and documentation', () {
    final db = module('DbModule');

    expect(db.id, 'db');
    expect(db.isGlobal, isTrue);
    expect(db.documentation, '/// Database access.');
    expect(db.location.path, 'lib/modules/basic.dart');
    expect(module('AppModule').id, 'AppModule');
    expect(db.invalidEntries, isEmpty);
  });

  test('class, Bind and Value providers', () {
    final providers = module('DbModule').providers;

    expect(
      [for (final p in providers) '${p.key}'],
      ['Repo', 'Clock', 'Token<String>(db.url)', 'AppConfig'],
    );
    expect((providers[1] as ClassProvider).injectable.type.name, 'SystemClock');
    final url = (providers[2] as ValueProvider).value as StringConstant;
    expect(url.value, 'postgres://localhost');
    final config = (providers[3] as ValueProvider).value as ReferenceConstant;
    expect(config.name, 'appConfig');
  });

  test('imports and exports: local class, function tear-off, keys', () {
    final app = module('AppModule');
    final db = module('DbModule');

    expect(app.invalidEntries, isEmpty);
    expect(app.imports.first, isA<LocalModuleReference>());
    final explicit = app.imports.last as OpaqueModuleReference;
    expect(explicit.name, 'explicitModule');
    expect(explicit.libraryUri, 'package:cases_app/modules/explicit.dart');
    final reexport = app.exports.single as ModuleReexport;
    expect(reexport.module.display, 'DbModule');
    expect(
      [for (final e in db.exports) '${(e as KeyExport).key}'],
      ['Repo', 'Token<String>(db.url)'],
    );
  });

  test('entries the generator cannot read become problems', () {
    final broken = module('BrokenModule');

    expect(broken.invalidEntries, [
      'imports: String is not a module.',
      'imports: a value of type String is not a module.',
      'providers: a value of type int is not a class, Bind<K, I>() or '
          'Value(v).',
      'providers: a value of type Token<String> is not a class, Bind<K, I>() '
          'or Value(v).',
      'providers: Value(...) of type int cannot be provided as '
          'Token<String>(db.url).',
      'controllers: Repo is not a @Controller class of this package.',
      'exports: a value of type int is not a class, token or module.',
    ]);
    expect(broken.imports, isEmpty);
    expect(broken.providers, isEmpty);
  });

  test('dependencies by type, by token and by required name', () {
    expect(dependencies('Repo'), [
      'clock: Clock',
      'url: Token<String>(db.url)',
      'config: AppConfig',
    ]);
    expect(injectable('Repo').constructor.dependencies.last.isNamed, isTrue);
    expect(dependencies('Fine'), [
      'clock: Clock',
      'port: Token<int>(port)',
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
      injectable('Named').constructor.problem,
      'Named has no unnamed constructor; dartnest creates it with Named(...).',
    );
  });

  test('parameters dependency injection cannot fill', () {
    expect(dependencies('Optional'), [
      'clock: Parameter clock of Optional is optional; dartnest injects '
          'required positional and required named parameters only.',
    ]);
    expect(dependencies('Odd'), [
      'clock: Parameter clock of Odd has type Clock?; dartnest injects '
          'non-nullable class types, or a Token with @Inject(token).',
      'callback: Parameter callback of Odd has type void Function(); dartnest '
          'injects non-nullable class types, or a Token with @Inject(token).',
    ]);
    expect(dependencies('BadTokens'), [
      'port: Parameter port of BadTokens has type int, but '
          'Token<String>(db.url) provides String.',
      'url: The @Inject argument of Parameter url of BadTokens is not a Token.',
    ]);
  });
}
