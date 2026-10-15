import 'package:grund/grund.dart';
import 'package:grund_http/testing.dart';
import 'package:grund/testing.dart';
import 'package:http_cases_app/apis/async_results.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';

final class _AsyncModule extends Module {
  const _AsyncModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AsyncLog>((i) => AsyncLog(), dependsOn: const []),
    Singleton<AsyncResultsApi>(
      (i) => AsyncResultsApi(i<AsyncLog>()),
      dependsOn: const [Key<AsyncLog>()],
    ),
    Singleton<AsyncResultsApiRoutes>(
      (i) => AsyncResultsApiRoutes(i, i<AsyncResultsApi>()),
      dependsOn: const [Key<AsyncResultsApi>()],
    ),
  ];
}

/// Handlers declared `FutureOr` run to completion before the response.
void main() {
  late TestApp app;
  late TestClient client;

  setUp(() async {
    app = await TestApp.start(root: TestRoot(const _AsyncModule()));
    client = TestClient.of(app);
  });

  tearDown(() => app.close());

  test('the 204 is sent only after the work completed', () async {
    final response = await client.delete('/async/7');

    expect(response.status, 204);
    expect(app.app.container.all<AsyncLog>().single.steps, ['removed 7']);
  });

  test('a throw after an await is a 500, not a zone error', () async {
    final response = await client.post('/async/boom');

    expect(response.status, 500);
  });

  test('a FutureOr value is awaited and serialized', () async {
    final response = await client.get('/async/3');

    expect(response.status, 200);
    expect(response.text, 'item 3');
  });
}
