// One suite, two module graphs: written by hand with the explicit API and
// generated from annotations. The generated graph must behave the same.
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/explicit.dart';
import 'package:users_app/users_app.dartnest.dart';

void main() {
  group('explicit', () => _suite(explicitAppModule));
  group('generated', () => _suite(appModule));
}

void _suite(Module Function() root) {
  late Application app; // Set in setUp before every test.
  late TestClient client; // Set in setUp before every test.
  final errors = <Object>[];

  setUp(() async {
    errors.clear();
    app = await Application.create(
      root,
      onError: (error, _) => errors.add(error),
    );
    client = TestClient(app);
  });

  tearDown(() => app.close());

  test('lists users with a query limit', () async {
    final response = await client.get('/users?limit=1');

    expect(response.status, 200);
    expect(response.json, [
      {'id': 1, 'name': 'ann'},
    ]);
    expect((await client.get('/users')).json, hasLength(2));
  });

  test('finds one user; a filter maps a domain error to 404', () async {
    expect((await client.get('/users/2')).json, {'id': 2, 'name': 'bob'});

    final missing = await client.get('/users/9');
    expect(missing.status, 404);
    expect((missing.json as Map)['message'], 'No user 9');
  });

  test('POST by an admin creates a user: 201 with location', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer admin'},
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cid'});
  });

  test('guards: 401 without a token, 403 for a non-admin', () async {
    final anonymous = await client.post('/users', json: {'name': 'cid'});
    final guest = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer guest'},
    );

    expect(anonymous.status, 401);
    expect(anonymous.headers['www-authenticate'], 'Bearer');
    expect(guest.status, 403);
  });

  test('malformed JSON, an invalid DTO and a bad int query are 400', () async {
    const admin = {'authorization': 'Bearer admin'};

    final malformed = await client.request(
      'POST',
      '/users',
      body: '{"name":',
      headers: admin,
    );
    final invalid = await client.post(
      '/users',
      json: {'name': ''},
      headers: admin,
    );
    final query = await client.get('/users?limit=ten');

    expect(malformed.status, 400);
    expect(invalid.status, 400);
    expect((invalid.json as Map)['message'], contains('"name"'));
    expect(query.status, 400);
  });

  test('a token value, a bound interface and a global module', () async {
    final named = await client.get('/hello', headers: {'x-name': 'ann'});

    expect(named.json, {
      'greeting': 'Hello, ann!',
      'at': '1970-01-01T00:00:00.000Z',
    });
    expect(
      (await client.get('/hello')).json,
      containsPair('greeting', 'Hello, world!'),
    );
  });

  test('an enum path parameter, and a void handler is 204', () async {
    expect((await client.get('/status/banned')).json, {'status': 'banned'});
    expect((await client.get('/status/gone')).status, 400);
    expect((await client.delete('/hello')).status, 204);
  });

  test('405 with allow, 404 for an unknown path, no errors', () async {
    final wrongMethod = await client.delete('/users');

    expect(wrongMethod.status, 405);
    expect(wrongMethod.headers['allow'], 'GET, HEAD, POST');
    expect((await client.get('/nope')).status, 404);
    expect(errors, isEmpty);
  });
}
