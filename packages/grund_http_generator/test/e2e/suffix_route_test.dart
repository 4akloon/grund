import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/testing.dart';

import '../helpers/fake_adapter.dart';

import 'package:http_cases_app/apis/suffix_route.dart';
import 'package:test/test.dart';

final class _SuffixModule extends Module {
  const _SuffixModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<SuffixRouteApi>((i) => SuffixRouteApi(), dependsOn: const []),
    Singleton<SuffixRouteApiRoutes>(
      (i) => SuffixRouteApiRoutes(i, i<SuffixRouteApi>()),
      dependsOn: const [Key<SuffixRouteApi>()],
    ),
  ];
}

/// Generated routes with a literal suffix reach the right handler.
void main() {
  late TestApp app;
  late TestClient client;

  setUp(() async {
    app = await TestApp.start(root: TestRoot(const _SuffixModule()));
    client = TestClient.of(app);
  });

  tearDown(() => app.close());

  test('the suffix route captures the value without the suffix', () async {
    final response = await client.get('/docs/7.json');

    expect(response.text, contains('json 7'));
  });

  test('the plain parameter route still answers the bare value', () async {
    final response = await client.get('/docs/7');

    expect(response.text, contains('plain 7'));
  });

  test('a multi-dot suffix and a nested suffix route match', () async {
    expect(
      (await client.get('/docs/pkg.tar.gz')).text,
      contains('archive pkg'),
    );
    expect(
      (await client.get('/docs/x/intro.md')).text,
      contains('markdown intro'),
    );
  });
}
