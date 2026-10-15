import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/users_app.dart';

import '../helpers/fake_adapter.dart';

/// The generated library compiles against the real core and HTTP packages,
/// and the application it wires answers requests.
void main() {
  late TestApp app;
  late TestClient client;

  setUp(() async {
    app = await TestApp.start(root: TestRoot(const AppModule()));
    client = TestClient.of(app);
  });

  tearDown(() => app.close());

  const admin = {'authorization': 'Bearer admin'};

  test('lists users, with a default and a validated limit', () async {
    final all = await client.get('/users');
    final one = await client.get('/users?limit=1&q=a');
    final tooMany = await client.get('/users?limit=101');

    expect(all.json, [
      {'id': 1, 'name': 'ann'},
      {'id': 2, 'name': 'bob'},
    ]);
    expect(one.json, [
      {'id': 1, 'name': 'ann'},
    ]);
    expect(tooMany.status, 400);
    expect((tooMany.json as Map)['code'], 'parameter_out_of_range');
  });

  test('a path parameter is an integer, a missing user is a 404', () async {
    final found = await client.get('/users/2');
    final missing = await client.get('/users/99');
    final bad = await client.get('/users/x');

    expect(found.json, {'id': 2, 'name': 'bob'});
    expect(missing.status, 404);
    expect((missing.json as Map)['code'], 'user_not_found');
    expect(bad.status, 400);
  });

  test('create answers 201 with a typed body, behind its hooks', () async {
    final anonymous = await client.post('/users', json: {'name': 'cy'});
    final viewer = await client.post(
      '/users',
      json: {'name': 'cy'},
      headers: {'authorization': 'Bearer viewer'},
    );
    final created = await client.post(
      '/users',
      json: {'name': 'cy'},
      headers: admin,
    );
    final invalid = await client.post('/users', json: {'x': 1}, headers: admin);

    expect(anonymous.status, 401);
    expect(viewer.status, 403);
    expect(created.status, 201);
    expect(created.json, {'id': 3, 'name': 'cy'});
    expect(invalid.status, 400);
    expect((invalid.json as Map)['code'], 'body_invalid');
  });

  test('a void result is a 204', () async {
    final removed = await client.delete('/users/1', headers: admin);
    final again = await client.delete('/users/1', headers: admin);

    expect(removed.status, 204);
    expect(again.status, 404);
    final audit = app.app.container.all<StringBuffer>().single;
    expect(audit.toString(), 'remove 1\n');
  });

  test('a call-scoped provider is created for every call', () async {
    final first = await client.get('/users/me', headers: {'accept': 'text/x'});
    final second = await client.get('/users/me');

    final one = first.json as Map;
    final two = second.json as Map;
    expect(one['greeting'], 'hello');
    expect(one['accept'], 'text/x');
    expect(two['accept'], isNull);
    expect(two['request'], (one['request'] as int) + 1);
  });

  test('a byte stream is sent as the body', () async {
    final response = await client.get('/users/export');

    expect(response.status, 200);
    expect(response.text, 'ann\nbob');
  });

  test('the server lists the routes of the generated API', () {
    expect(app.app.container.all<HttpServer>().single.routes, [
      'DELETE /users/:id',
      'GET /users',
      'GET /users/:id',
      'GET /users/export',
      'GET /users/me',
      'POST /users',
    ]);
  });
}
