import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

final class EchoApi extends HttpApi {
  EchoApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/echo', (_) => 'ok'),
    Route.post('/echo', (_) => 'ok'),
    Route.delete('/echo', (_) => 'ok'),
  ];
}

final class EchoModule extends Module {
  const EchoModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SameOriginHook>.instance(SameOriginHook())]),
    IoAdapterModule(),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<EchoApi>(EchoApi.new, dependsOn: const []),
  ];
}

void main() {
  // Assigned in setUp, which runs before every test.
  late TestClient client;

  setUp(() async {
    final app = await TestApp.start(root: const EchoModule());
    addTearDown(app.close);
    client = TestClient.of(app);
  });

  Future<int> post(Map<String, String> headers) async =>
      (await client.post('/echo', headers: headers)).status;

  test('a POST without browser headers passes', () async {
    expect(await post({}), 200);
  });

  test('a GET from another site passes', () async {
    final response = await client.get(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 200);
  });

  for (final site in ['same-origin', 'none']) {
    test('a POST with sec-fetch-site $site passes', () async {
      expect(await post({'sec-fetch-site': site}), 200);
    });
  }

  for (final site in ['same-site', 'cross-site']) {
    test('a POST with sec-fetch-site $site is a 403', () async {
      expect(await post({'sec-fetch-site': site}), 403);
    });
  }

  test('a DELETE from another site is a 403', () async {
    final response = await client.delete(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 403);
  });

  test('an origin that names the host passes, in any case', () async {
    expect(
      await post({
        'origin': 'http://Example.test:8080',
        'host': 'example.test:8080',
      }),
      200,
    );
    expect(
      await post({'origin': 'https://example.test', 'host': 'example.test'}),
      200,
    );
    expect(
      await post({'origin': 'http://[::1]:8080', 'host': '[::1]:8080'}),
      200,
    );
  });

  test('an origin of another host or port is a 403', () async {
    expect(
      await post({'origin': 'http://evil.test', 'host': 'example.test'}),
      403,
    );
    expect(
      await post({
        'origin': 'http://example.test:9',
        'host': 'example.test:8080',
      }),
      403,
    );
  });

  test('origin null or an origin without a host header is a 403', () async {
    expect(await post({'origin': 'null', 'host': 'example.test'}), 403);
    expect(await post({'origin': 'http://example.test'}), 403);
  });

  test(
    'a matching origin does not excuse a cross-site sec-fetch-site',
    () async {
      expect(
        await post({
          'origin': 'http://example.test',
          'host': 'example.test',
          'sec-fetch-site': 'cross-site',
        }),
        403,
      );
    },
  );
}
