import 'package:grund_generator/src/constructs/dependency_check.dart';
import 'package:grund_generator/src/model/controller_model.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/module_reference.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  final provider = GraphModels.provider;
  final module = GraphModels.module;

  List<String> check(
    List<ModuleModel> modules, [
    List<ControllerModel> controllers = const [],
  ]) => [
    for (final d in DependencyCheck.check(
      GraphModels.package(modules, controllers),
    ))
      d.message,
  ];

  test('a class that needs itself is a one-step cycle', () {
    final found = check([
      module(
        'App',
        providers: [
          provider('Loop', ['Loop']),
        ],
      ),
    ]);

    expect(found, ['Circular dependency: Loop -> Loop.']);
  });

  test('a diamond is not a cycle', () {
    final found = check([
      module(
        'App',
        providers: [
          provider('Top', ['Left', 'Right']),
          provider('Left', ['Base']),
          provider('Right', ['Base']),
          provider('Base'),
        ],
      ),
    ]);

    expect(found, isEmpty);
  });

  test('a cycle through two modules is reported once', () {
    final found = check([
      module(
        'Core',
        isGlobal: true,
        imports: [GraphModels.reference('Db')],
        providers: [
          provider('X', ['Y']),
        ],
        exports: [KeyExport(GraphModels.key('X'))],
      ),
      module(
        'Db',
        providers: [
          provider('Y', ['X']),
        ],
        exports: [KeyExport(GraphModels.key('Y'))],
      ),
    ]);

    expect(found, ['Circular dependency: X -> Y -> X.']);
  });

  test('a class only the importer provides is missing for its owner', () {
    final found = check([
      module(
        'A',
        imports: [GraphModels.reference('B')],
        providers: [
          provider('X', ['Y']),
        ],
      ),
      module(
        'B',
        providers: [
          provider('Y', ['X']),
        ],
        exports: [KeyExport(GraphModels.key('Y'))],
      ),
    ]);

    expect(found, [
      'No provider for X in module "B" (resolving: Y). It is declared in '
          'module(s) [A]; export it there and import that module into "B".',
    ]);
  });

  test('a dense graph is checked in linear time', () {
    const layers = 40;
    final providers = [
      for (var layer = 0; layer < layers; layer++)
        for (var i = 0; i < 2; i++)
          provider('L$layer$i', [
            if (layer < layers - 1) ...['L${layer + 1}0', 'L${layer + 1}1'],
          ]),
    ];

    final stopwatch = Stopwatch()..start();
    final found = check([module('App', providers: providers)]);

    expect(found, isEmpty);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a dense graph with a cycle at the bottom reports one per entry', () {
    const layers = 40;
    final providers = [
      for (var layer = 0; layer < layers; layer++)
        for (var i = 0; i < 2; i++)
          provider('L$layer$i', [
            if (layer < layers - 1) ...['L${layer + 1}0', 'L${layer + 1}1'],
            if (layer == layers - 1) 'L00',
          ]),
    ];

    final found = check([module('App', providers: providers)]);

    expect(found, hasLength(2));
    expect(found, everyElement(startsWith('Circular dependency: ')));
  });

  test('a re-exported opaque module turns the check off', () {
    final found = check([
      module(
        'App',
        providers: [
          provider('Needy', ['Absent']),
        ],
        exports: [
          const ModuleReexport(
            OpaqueModuleReference(name: 'm', libraryUri: 'package:x/x.dart'),
          ),
        ],
      ),
    ]);

    expect(found, isEmpty);
  });

  test(
    'a missing provider is reported without a hint when none declares it',
    () {
      final found = check([
        module(
          'App',
          providers: [
            provider('Needy', ['Absent']),
          ],
        ),
      ]);

      expect(found, [
        'No provider for Absent in module "App" (resolving: Needy).',
      ]);
    },
  );

  test('a guard on the controller and on its route is reported once', () {
    final found = check(
      [
        module('App', controllers: [GraphModels.type('Api')]),
      ],
      [GraphModels.controller('Api', guard: 'Gate')],
    );

    expect(found, ['No provider for Gate in module "App" (resolving: Api).']);
  });

  test('a controller that was not collected is skipped', () {
    final found = check([
      module('App', controllers: [GraphModels.type('Elsewhere')]),
    ]);

    expect(found, isEmpty);
  });
}
