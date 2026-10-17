import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/module_reference.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    package = await fixture.collect([
      'lib/modules/invalid_entries.dart',
      'lib/modules/basic.dart',
      'lib/modules/lookalike.dart',
    ]);
  });

  ModuleModel module(String name) =>
      package.modules.firstWhere((m) => m.type.name == name);

  test('the source libraries are listed by package-relative path', () {
    expect(package.libraryPaths, [
      'lib/modules/basic.dart',
      'lib/modules/invalid_entries.dart',
      'lib/modules/lookalike.dart',
    ]);
  });

  test('modules come in library URI order', () {
    expect(package.languageVersion.toString(), '3.13.0');
    expect(
      [for (final m in package.modules) m.type.name],
      ['DbModule', 'AppModule', 'BrokenModule'],
    );
  });

  test('a module keeps its flags, location and documentation', () {
    final db = module('DbModule');

    expect(db.isGlobal, isTrue);
    expect(db.extendsModule, isTrue);
    expect(db.documentation, '/// Database access.');
    expect(db.location.path, 'lib/modules/basic.dart');
    expect(module('AppModule').isGlobal, isFalse);
    expect(db.invalidEntries, isEmpty);
  });

  test('class and Bind providers are keyed by what they provide', () {
    final providers = module('DbModule').providers;

    expect(
      [for (final p in providers) "${p.key} <- ${p.injectable.type}"],
      [
        'Repo <- Repo',
        'Clock <- SystemClock',
        "PrimaryDb('primary') <- PrimaryDb",
        'Tx <- Tx',
      ],
    );
    expect(providers.last.injectable.lifetime, Lifetime.scoped);
  });

  test('@Provides methods keep key, scope and async-ness', () {
    final provides = module('DbModule').provides;

    expect(provides.first.key.toString(), 'AppConfig');
    expect(provides.first.lifetime, Lifetime.singleton);
    final session = provides[1];
    expect("${session.key}", "Session('main')");
    expect(session.lifetime, Lifetime.scoped);
    expect(session.isAsync, isTrue);
    expect("${session.dependencies.single.key}", 'Clock');
  });

  test('a @Provides method that cannot be called has a problem', () {
    final [_, _, notStatic, nothing] = module('DbModule').provides;

    expect(notStatic.problem, contains('is not static'));
    expect(nothing.problem, contains('returns void'));
    expect(notStatic.key, isNull);
  });

  test('imports are local or opaque, re-exports and keys are exports', () {
    final app = module('AppModule');
    final db = module('DbModule');

    expect(app.imports.first, isA<LocalModuleReference>());
    expect(app.imports.last, isA<OpaqueModuleReference>());
    expect(app.imports.last.display, 'ExplicitModule');
    expect((app.exports.single as ModuleReexport).type.display, 'DbModule');
    expect(
      [for (final e in db.exports) '${(e as KeyExport).key}'],
      ['Repo', "PrimaryDb('primary')", 'Clock', "Session('main')"],
    );
  });

  test('entries the generator cannot read become problems', () {
    final broken = module('BrokenModule');

    expect(broken.extendsModule, isFalse);
    expect(broken.invalidEntries, [
      'imports: String is not a const instance of a Module.',
      'imports: a value of type String is not a const instance of a Module.',
      'imports: a value of type Module is not a const instance of a Module.',
      'providers: a value of type int is not a class or Bind<I, C>().',
      'providers: a value of type Label is not a class or Bind<I, C>().',
      'exports: a value of type int is not a class, a Key<T>() or an '
          'imported module.',
    ]);
    expect(broken.imports, isEmpty);
    expect(broken.providers, isEmpty);
  });

  test('a class named Module from another library is not a module', () {
    expect(package.modules.where((m) => m.type.name == 'NotOurs'), isEmpty);
  });
}
