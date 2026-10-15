import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

ProvidesModel _async(Lifetime lifetime) => ProvidesModel(
  owner: GraphModels.type('AppModule'),
  methodName: 'session',
  location: const SourceLocation('lib/app.dart', 6, 3),
  key: GraphModels.key('Session'),
  lifetime: lifetime,
  isAsync: true,
);

List<String> _codes(Lifetime lifetime) => GraphModels.codes(
  GraphModels.package([
    GraphModels.module('AppModule', provides: [_async(lifetime)]),
  ]),
);

void main() {
  test('an async singleton @Provides is fine', () {
    expect(_codes(Lifetime.singleton), isEmpty);
  });

  test('an async call-scoped @Provides is invalid', () {
    expect(_codes(Lifetime.scoped), ['invalid_provides']);
  });

  test('an async transient @Provides is invalid', () {
    expect(_codes(Lifetime.transient), ['invalid_provides']);
  });
}
