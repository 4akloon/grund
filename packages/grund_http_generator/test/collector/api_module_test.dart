import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';
import '../helpers/graph_models.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open(
      'http_cases_app',
    ).collect(['lib/modules/with_api.dart', 'lib/apis/tasks.dart']);
  });

  ProviderModel provider(String name) => package.modules.single.providers
      .firstWhere((p) => p.injectable.type.name == name);

  test('an @Api class is an injectable provider without @Injectable', () {
    expect(package.modules.single.type.name, 'TasksModule');
    expect(provider('TasksApi').injectable.isAnnotated, isTrue);
    expect(GraphModels.codes(package), isEmpty);
  });

  test('the api construct claims an @Api provider with its hooks', () {
    final claims = ProviderClaims.collect(package, FixturePackage.constructs);

    expect(claims.claimed(provider('ApiKeyHook')), isNull);
    expect([
      for (final lookup in claims.claimed(provider('TasksApi'))!.lookups)
        '${lookup.key}',
    ], contains('ApiKeyHook'));
  });
}
