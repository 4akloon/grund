// The whole stack through TestClient: routing, guards, pipes, filters,
// serialization and errors, without a server.
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';

enum Status { active, banned }

/// `GET /status/:status` echoes an enum path parameter.
Module statusModule() => Module(
  id: 'status',
  controllers: [
    Controller<Object>(
      path: '/status',
      create: (i) => Object(),
      routes: [
        Route.get(
          '/:status',
          (c, ctx) async => {
            'status': (await ctx.param<Status>(
              'status',
              pipes: const [EnumPipe(Status.values)],
            )).name,
          },
        ),
      ],
    ),
  ],
);

void main() {
  late Application app; // Set in setUp before every test.
  late TestClient client; // Set in setUp before every test.
  final errors = <Object>[];

  setUp(() async {
    errors.clear();
    app = await Application.create(
      () => Module(id: 'app', imports: [usersModule(), statusModule()]),
      onError: (error, _) => errors.add(error),
    );
    client = TestClient(app);
  });

  tearDown(() => app.close());

  test('lists users with a query limit', () async {
    final response = await client.get('/users?limit=1');

    expect(response.status, 200);
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(response.json, [
      {'id': 1, 'name': 'ann'},
    ]);
  });

  test('finds one user by an int path parameter', () async {
    expect((await client.get('/users/2')).json, {'id': 2, 'name': 'bob'});
  });

  test('a filter maps a domain error to 404', () async {
    final response = await client.get('/users/9');

    expect(response.status, 404);
    expect(response.json, {
      'statusCode': 404,
      'error': 'Not Found',
      'message': 'No user 9',
    });
  });

  test('POST creates a user: 201 with location', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer admin'},
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cid'});
  });

  test('POST without a token is 401 with www-authenticate', () async {
    final response = await client.post('/users', json: {'name': 'cid'});

    expect(response.status, 401);
    expect(response.headers['www-authenticate'], 'Bearer');
  });

  test('POST by a non-admin is 403', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer guest'},
    );

    expect(response.status, 403);
    expect((response.json as Map)['message'], 'Forbidden resource');
  });

  test('malformed JSON and an invalid DTO are 400', () async {
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

    expect(malformed.status, 400);
    expect(invalid.status, 400);
    expect((invalid.json as Map)['message'], contains('"name"'));
  });

  test('an invalid int query is 400', () async {
    final response = await client.get('/users?limit=ten');

    expect(response.status, 400);
    expect((response.json as Map)['message'], contains('limit'));
  });

  test('a wrong method is 405 with allow, an unknown path is 404', () async {
    final wrongMethod = await client.delete('/users');
    final unknown = await client.get('/nope');

    expect(wrongMethod.status, 405);
    expect(wrongMethod.headers['allow'], 'GET, HEAD, POST');
    expect(unknown.status, 404);
    expect(errors, isEmpty);
  });

  test('EnumPipe converts a path parameter by name', () async {
    expect((await client.get('/status/banned')).json, {'status': 'banned'});

    final invalid = await client.get('/status/gone');
    expect(invalid.status, 400);
    expect(
      (invalid.json as Map)['message'],
      'Invalid path parameter "status": expected one of active, banned, '
      'got "gone".',
    );
  });

  test('after close every request is 503', () async {
    await app.close();

    expect((await client.get('/users')).status, 503);
  });
}
