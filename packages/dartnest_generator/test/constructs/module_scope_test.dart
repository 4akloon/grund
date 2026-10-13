import 'package:dartnest_generator/src/constructs/module_scope.dart';
import 'package:dartnest_generator/src/model/module_export.dart';
import 'package:dartnest_generator/src/model/module_reference.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  final key = GraphModels.key;
  final provider = GraphModels.provider;
  final module = GraphModels.module;
  final reference = GraphModels.reference;

  test('own providers, exports of imports and of global modules', () {
    final core = module(
      'Core',
      providers: [provider('Log')],
      isGlobal: true,
      exports: [KeyExport(key('Log'))],
    );
    final db = module(
      'Db',
      providers: [provider('Repo'), provider('Hidden')],
      exports: [KeyExport(key('Repo'))],
    );
    final app = module(
      'App',
      imports: [reference('Db')],
      providers: [provider('Service')],
    );
    final scope = ModuleScope([app, core, db]);

    final visible = scope.visibleIn(app);

    expect(
      visible.keys,
      unorderedEquals([key('Log'), key('Repo'), key('Service')]),
    );
    expect(visible[key('Repo')]!.owner, db);
    expect(identical(scope.visibleIn(app), visible), isTrue);
  });

  test('a module re-exports an imported module', () {
    final inner = module(
      'Inner',
      providers: [provider('Deep')],
      exports: [KeyExport(key('Deep'))],
    );
    final outer = module(
      'Outer',
      imports: [reference('Inner')],
      exports: [ModuleReexport(reference('Inner'))],
    );
    final app = module('App', imports: [reference('Outer')]);

    expect(ModuleScope([app, outer, inner]).visibleIn(app).keys, [key('Deep')]);
  });

  test('an own provider wins over an export of an import', () {
    final db = module(
      'Db',
      providers: [provider('Repo')],
      exports: [KeyExport(key('Repo'))],
    );
    final app = module(
      'App',
      imports: [reference('Db')],
      providers: [provider('Repo')],
    );

    expect(ModuleScope([app, db]).visibleIn(app)[key('Repo')]!.owner, app);
  });

  test('unknown and opaque modules contribute nothing', () {
    final app = module(
      'App',
      imports: [
        reference('Missing'),
        const OpaqueModuleReference(name: 'm', libraryUri: 'package:x/x.dart'),
      ],
    );

    expect(ModuleScope([app]).visibleIn(app), isEmpty);
  });

  test('declaring lists the ids of the modules that provide a key', () {
    final a = module('A', providers: [provider('Repo')]);
    final b = module('B', providers: [provider('Other'), provider('Repo')]);

    expect(ModuleScope([a, b]).declaring(key('Repo')), ['A', 'B']);
    expect(ModuleScope([a, b]).declaring(key('Nope')), isEmpty);
  });
}
