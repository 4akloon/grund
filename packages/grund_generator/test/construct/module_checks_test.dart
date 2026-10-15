import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/constructor_model.dart';
import 'package:grund_generator/src/model/dependency_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/provider_model.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

const _at = SourceLocation('lib/app.dart', 1, 1);

ProviderModel _custom(
  String name, {
  ConstructorModel constructor = const ConstructorModel([]),
  bool isAnnotated = true,
  String? qualifier,
}) => ProviderModel(
  GraphModels.key(name, qualifier),
  InjectableModel(
    type: GraphModels.type(name),
    lifetime: Lifetime.singleton,
    isAnnotated: isAnnotated,
    constructor: constructor,
    location: _at,
    name: qualifier,
  ),
);

List<String> _codes(List<ModuleModel> modules) =>
    GraphModels.codes(GraphModels.package([...modules]));

void main() {
  test('modules importing each other are circular_module_import', () {
    final a = GraphModels.module('A', imports: [GraphModels.reference('B')]);
    final b = GraphModels.module('B', imports: [GraphModels.reference('A')]);

    expect(_codes([a, b]), ['circular_module_import']);
  });

  test('exporting a key the module does not bind is invalid_export', () {
    final module = GraphModels.module(
      'App',
      exports: [GraphModels.export('Missing')],
    );

    expect(_codes([module]), ['invalid_export']);
  });

  test('re-exporting a module that is not imported is invalid_export', () {
    final module = GraphModels.module(
      'App',
      exports: [ModuleReexport(GraphModels.type('Other'))],
    );

    expect(_codes([module]), ['invalid_export']);
  });

  test('a module not extending Module is invalid_module_class', () {
    final module = GraphModels.module('App', extendsModule: false);

    expect(_codes([module]), ['invalid_module_class']);
  });

  test('an unreadable entry is invalid_module_entry', () {
    final module = GraphModels.module('App', invalidEntries: ['imports: 42']);

    expect(_codes([module]), ['invalid_module_entry']);
  });

  test('an empty @Named name is invalid_name', () {
    final module = GraphModels.module(
      'App',
      providers: [_custom('A', qualifier: '')],
    );

    expect(_codes([module]), ['invalid_name']);
  });

  test('a provider without a usable constructor is invalid_constructor', () {
    final module = GraphModels.module(
      'App',
      providers: [
        _custom('A', constructor: const ConstructorModel.invalid('x')),
      ],
    );

    expect(_codes([module]), ['invalid_constructor']);
  });

  test('a parameter that cannot be injected is invalid_dependency', () {
    const dependency = DependencyModel.invalid(
      name: 'x',
      isNamed: false,
      location: _at,
      problem: 'It is a primitive.',
    );
    final module = GraphModels.module(
      'App',
      providers: [
        _custom('A', constructor: const ConstructorModel([dependency])),
      ],
    );

    expect(_codes([module]), ['invalid_dependency']);
  });

  test('a provider without @Injectable is not_injectable', () {
    final module = GraphModels.module(
      'App',
      providers: [_custom('A', isAnnotated: false)],
    );

    expect(_codes([module]), ['not_injectable']);
  });

  test('an import that cannot be written is unsupported_constant', () {
    final module = GraphModels.module(
      'App',
      imports: [GraphModels.unwritable('Lib')],
    );

    expect(_codes([module]), ['unsupported_constant']);
  });

  test('a binding key is unique per module and name', () {
    final module = GraphModels.module(
      'App',
      providers: [
        _custom('A'),
        _custom('A', qualifier: 'main'),
      ],
    );

    expect(_codes([module]), isEmpty);
  });

  test('an unrelated own diagnostic does not hide dependency errors', () {
    final module = GraphModels.module(
      'App',
      invalidEntries: ['imports: 42'],
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(
      _codes([module]),
      unorderedEquals(['invalid_module_entry', 'missing_provider']),
    );
  });

  test('an invalid export stops the dependency check', () {
    final module = GraphModels.module(
      'App',
      exports: [GraphModels.export('Missing')],
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(_codes([module]), ['invalid_export']);
  });
}
