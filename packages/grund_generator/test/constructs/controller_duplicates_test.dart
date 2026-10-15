import 'package:grund_generator/src/constructs/controller_construct.dart';
import 'package:grund_generator/src/model/controller_model.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:test/test.dart';

import '../helpers/controller_models.dart';
import '../helpers/graph_models.dart';

ControllerModel _inLibrary(String library) {
  final base = ControllerModels.controller('Same', '/x', [
    ControllerModels.route('GET', '/'),
  ]);
  return ControllerModel(
    type: TypeModel(
      name: 'Same',
      kind: TypeKind.interface,
      libraryUri: 'package:app/$library.dart',
    ),
    path: base.path,
    constructor: base.constructor,
    location: base.location,
    routes: base.routes,
  );
}

List<String> _messages(PackageModel package) => [
  for (final d in const ControllerConstruct().validate(package))
    '${d.code.id}: ${d.message}',
];

void main() {
  test('same-named controllers in different libraries do not share a key', () {
    final messages = _messages(
      ControllerModels.package([_inLibrary('a'), _inLibrary('b')]),
    );

    expect(messages, [
      'duplicate_route: Route GET /x is declared twice: by Same.handle and '
          'by Same.handle. Parameter names do not distinguish routes.',
    ]);
  });

  test('one controller class is not a duplicate of itself', () {
    expect(_messages(ControllerModels.package([_inLibrary('a')])), isEmpty);
  });

  test('a controller listed by two modules is reported at the second', () {
    final package = GraphModels.package(
      [
        GraphModels.module('One', controllers: [GraphModels.type('A')]),
        GraphModels.module('Two', controllers: [GraphModels.type('A')]),
      ],
      [GraphModels.controller('A', guard: 'G')],
    );

    expect(_messages(package), [
      'duplicate_route: Controller A is listed by modules One and Two; its '
          'routes would be registered twice. List it in one module only.',
    ]);
  });
}
