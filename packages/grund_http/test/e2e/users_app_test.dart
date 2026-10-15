import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/users_app.dart';

/// The users application, written in the explicit form, driven through
/// `TestClient`.
void main() {
  late TestApp app;
  late TestClient client;

  Future<void> startApp({HttpModule http = const HttpModule()}) async {
    app = await TestApp.start(root: UsersAppModule(FakeAdapter(), http: http));
    client = TestClient.of(app);
  }

  setUp(startApp);
  tearDown(() => app.close());

  Map<String, String> bearer(String role) => {'authorization': 'Bearer $role'};

  test('lists users with a query limit', () async {
    final all = await client.get('/users');
    final one = await client.get('/users?limit=1');

    expect(all.status, 200);
    expect(all.json, [
      {'id': 1, 'name': 'ann'},
      {'id': 2, 'name': 'bob'},
    ]);
    expect(one.json, [
      {'id': 1, 'name': 'ann'},
    ]);
  });

  test('finds one user by an integer path parameter', () async {
    final response = await client.get('/users/2');

    expect(response.json, {'id': 2, 'name': 'bob'});
    expect(response.headers['content-type'], 'application/json; charset=utf-8');
  });

  test('a hook turns a domain error into a 404 problem', () async {
    final response = await client.get('/users/99');

    expect(response.status, 404);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.json, {
      'type': 'about:blank',
      'title': 'Not Found',
      'status': 404,
      'detail': 'No user 99',
      'instance': '/users/99',
      'code': 'user_not_found',
    });
  });

  test('POST creates a user: 201 with location', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cy'},
      headers: bearer('admin'),
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cy'});
    expect((await client.get('/users/3')).status, 200);
  });

  test('POST without a token is 401 with www-authenticate', () async {
    final response = await client.post('/users', json: {'name': 'cy'});

    expect(response.status, 401);
    expect(response.headers['www-authenticate'], 'Bearer');
    expect((response.json as Map)['title'], 'Unauthorized');
  });

  test(
    'POST by a non-admin is 403 and the hook order is auth, roles',
    () async {
      final response = await client.post(
        '/users',
        json: {'name': 'cy'},
        headers: bearer('viewer'),
      );

      expect(response.status, 403);
      expect((response.json as Map)['code'], 'role_not_allowed');
    },
  );

  group('bad input is a 4xx problem, never a 500 (RF-3)', () {
    test('malformed JSON', () async {
      final response = await client.request(
        'POST',
        '/users',
        body: '{"name":',
        headers: bearer('admin'),
      );

      expect(response.status, 400);
      expect((response.json as Map)['code'], 'body_invalid');
    });

    test('a JSON value that is not an object', () async {
      final response = await client.post(
        '/users',
        json: [1, 2],
        headers: bearer('admin'),
      );

      expect(response.status, 400);
      expect((response.json as Map)['code'], 'body_invalid');
    });

    test('a missing required field', () async {
      final response = await client.post(
        '/users',
        json: <String, Object?>{},
        headers: bearer('admin'),
      );

      expect(response.status, 400);
      expect(
        ((response.json as Map)['errors'] as List).single,
        containsPair('pointer', '/body'),
      );
    });

    test('a number that is not a number', () async {
      final response = await client.get('/users?limit=ten');

      expect(response.status, 400);
      expect(((response.json as Map)['errors'] as List).single, {
        'detail':
            'Invalid query parameter "limit": expected an integer, '
            'got "ten".',
        'pointer': '/query/limit',
        'code': 'parameter_invalid',
      });
    });

    test('a path parameter of the wrong type', () async {
      final response = await client.get('/users/abc');

      expect(response.status, 400);
      expect((response.json as Map)['code'], 'parameter_invalid');
    });

    test('a body over the configured limit is a 413', () async {
      await app.close();
      await startApp(
        http: const HttpModule(config: HttpConfig(maxBodyBytes: 16)),
      );

      final response = await client.post(
        '/users',
        json: {'name': 'a name that is far too long'},
        headers: bearer('admin'),
      );

      expect(response.status, 413);
      expect((response.json as Map)['code'], 'body_too_large');
    });

    test('a wrong method is 405 with allow, an unknown path is 404', () async {
      final wrongMethod = await client.delete('/users/1');
      final unknown = await client.get('/nothing');

      expect(wrongMethod.status, 405);
      expect(wrongMethod.headers['allow'], 'GET, HEAD');
      expect(unknown.status, 404);
      expect(unknown.headers['content-type'], 'application/problem+json');
    });

    test('extra slashes and percent-encoding in the path', () async {
      expect((await client.get('/users//1/')).status, 200);
      expect((await client.get('/users/%31')).status, 200);
    });
  });

  test('after close every request is 503', () async {
    await app.close();

    final response = await client.get('/users/1');

    expect(response.status, 503);
    expect((response.json as Map)['code'], 'server_unavailable');
  });
}
