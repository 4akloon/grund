import 'package:dartnest_generator/src/constructs/module_structure_check.dart';
import 'package:dartnest_generator/src/model/module_model.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

/// [layers] layers of two modules, each importing both modules of the next.
List<ModuleModel> _denseLayers(int layers) => [
  for (var layer = 0; layer < layers; layer++)
    for (final side in ['a', 'b'])
      GraphModels.module(
        'M$layer$side',
        imports: [
          if (layer + 1 < layers)
            for (final next in ['a', 'b'])
              GraphModels.reference('M${layer + 1}$next'),
        ],
      ),
];

void main() {
  test('a dense layered module DAG is checked in linear time', () {
    final found = ModuleStructureCheck.check(_denseLayers(25)).toList();

    expect(found, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('a cycle behind a dense DAG is still reported once', () {
    final modules = [
      ..._denseLayers(25),
      GraphModels.module('Back', imports: [GraphModels.reference('M0a')]),
    ];
    final tail = modules.firstWhere((m) => m.id == 'M24a');
    modules[modules.indexOf(tail)] = GraphModels.module(
      'M24a',
      imports: [GraphModels.reference('M0a')],
    );

    final found = ModuleStructureCheck.check(modules).toList();

    expect(found.map((d) => d.message), [
      startsWith('Module imports form a cycle: M0a -> '),
    ]);
  });
}
