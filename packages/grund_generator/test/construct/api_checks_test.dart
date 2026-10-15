import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/constructor_model.dart';
import 'package:grund_generator/src/model/hook_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

InjectableModel _apiInjectable(Lifetime lifetime) => InjectableModel(
  type: GraphModels.type('Api'),
  lifetime: lifetime,
  isAnnotated: true,
  isApi: true,
  constructor: const ConstructorModel([]),
  location: const SourceLocation('lib/app.dart', 1, 1),
);

void main() {
  test('an api with a non-singleton @Injectable is invalid_api', () {
    final package = GraphModels.package(
      [
        GraphModels.module(
          'App',
          providers: [GraphModels.provider('Api', lifetime: Lifetime.scoped)],
        ),
      ],
      apis: [GraphModels.api('Api')],
      injectables: [_apiInjectable(Lifetime.scoped)],
    );

    expect(GraphModels.codes(package), ['invalid_api']);
  });

  test('an api provided by two modules is duplicate_api', () {
    final package = GraphModels.package(
      [
        GraphModels.module('One', providers: [GraphModels.provider('Api')]),
        GraphModels.module('Two', providers: [GraphModels.provider('Api')]),
      ],
      apis: [GraphModels.api('Api')],
    );

    expect(GraphModels.codes(package), ['duplicate_api']);
  });

  test('an api provided by one module is accepted', () {
    final package = GraphModels.package(
      [
        GraphModels.module('One', providers: [GraphModels.provider('Api')]),
      ],
      apis: [GraphModels.api('Api')],
    );

    expect(GraphModels.codes(package), isEmpty);
  });

  test('an api hook that cannot be written is unsupported_constant', () {
    final hook = HookModel(
      type: GraphModels.type('Hook'),
      isInstance: true,
      expression: const UnsupportedConstant('it is private'),
    );
    final package = GraphModels.package(
      [
        GraphModels.module(
          'App',
          providers: [
            GraphModels.provider('Api'),
            GraphModels.provider('Hook'),
          ],
        ),
      ],
      apis: [
        GraphModels.api('Api', use: [hook]),
      ],
    );

    expect(GraphModels.codes(package), ['unsupported_constant']);
  });
}
