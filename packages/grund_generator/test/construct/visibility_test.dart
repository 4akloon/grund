import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

List<String> _codes(List<ModuleModel> modules) =>
    GraphModels.codes(GraphModels.package([...modules]));

void main() {
  final needsB = GraphModels.provider('A', needs: ['B']);

  test('an own binding is visible', () {
    final app = GraphModels.module(
      'App',
      providers: [needsB, GraphModels.provider('B')],
    );

    expect(_codes([app]), isEmpty);
  });

  test('an import makes only the exports of the module visible', () {
    final exporting = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final hiding = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
    );
    final app = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Lib')],
      providers: [needsB],
    );

    expect(_codes([exporting, app]), isEmpty);
    expect(_codes([hiding, app]), ['missing_provider']);
  });

  test('a global module is visible without an import, by its exports', () {
    ModuleModel build({required bool exported}) => GraphModels.module(
      'Glob',
      isGlobal: true,
      providers: [GraphModels.provider('B')],
      exports: exported ? [GraphModels.export('B')] : [],
    );
    final app = GraphModels.module('App', providers: [needsB]);

    expect(_codes([build(exported: true), app]), isEmpty);
    expect(_codes([build(exported: false), app]), ['missing_provider']);
  });

  test('an own binding shadows an imported one', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final app = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Lib')],
      providers: [
        needsB,
        GraphModels.provider('B', lifetime: Lifetime.scoped),
      ],
    );

    expect(_codes([lib, app]), ['captive_dependency']);
  });

  test('an imported binding shadows a global one', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final glob = GraphModels.module(
      'Glob',
      isGlobal: true,
      providers: [GraphModels.provider('B', lifetime: Lifetime.scoped)],
      exports: [GraphModels.export('B')],
    );
    final app = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Lib')],
      providers: [needsB],
    );

    expect(_codes([lib, glob, app]), isEmpty);
  });

  test('a re-exported module is visible through the re-exporter', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final mid = GraphModels.module(
      'Mid',
      imports: [GraphModels.reference('Lib')],
      exports: [ModuleReexport(GraphModels.type('Lib'))],
    );
    final silent = GraphModels.module(
      'Mid',
      imports: [GraphModels.reference('Lib')],
    );
    final app = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Mid')],
      providers: [needsB],
    );

    expect(_codes([lib, mid, app]), isEmpty);
    expect(_codes([lib, silent, app]), ['missing_provider']);
  });

  test('an opaque import hides keys no local module binds', () {
    final plain = GraphModels.module('App', providers: [needsB]);
    final opaque = GraphModels.module(
      'App',
      imports: [GraphModels.opaque('Ext')],
      providers: [needsB],
    );

    expect(_codes([plain]), ['missing_provider']);
    expect(_codes([opaque]), isEmpty);
  });

  test('an opaque import still reports keys a local module binds', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
    );
    final app = GraphModels.module(
      'App',
      imports: [GraphModels.opaque('Ext')],
      providers: [needsB],
    );

    expect(_codes([lib, app]), ['missing_provider']);
  });
}
