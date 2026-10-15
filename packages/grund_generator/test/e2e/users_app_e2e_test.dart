// One suite, two module graphs: written by hand with the explicit API and
// generated from annotations. The generated graph must behave the same.
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/explicit.dart';
import 'package:users_app/users_app.grund.dart';

void main() {
  group('explicit', () => _suite(explicitAppModule));
  group('generated', () => _suite(appModule));
}

/// The application of one test and the errors it reported.
final class _Harness {
  /// The application under test, created by [register]'s `setUp`.
  late Application app; // Set in setUp before every test.

  /// The client of [app], set together with it.
  late TestClient client; // Set in setUp before every test.

  /// The errors the application reported.
  final errors = <Object>[];

  /// Registers `setUp` and `tearDown` that create and close the application
  /// built from [root].
  void register(Module Function() root) {
    setUp(() async {
      errors.clear();
      app = await Application.create(
        root,
        onError: (error, _) => errors.add(error),
      );
      client = TestClient(app);
    });
    tearDown(() => app.close());
  }
}

void _suite(Module Function() root) {
  final harness = _Harness()..register(root);
  _reading(harness);
  _writing(harness);
  _invalidInput(harness);
  _wiring(harness);
  _routing(harness);
}

/// Reading users: query, path and the not-found filter.
void _reading(_Harness h) {
  test('lists users with a query limit', () async {
    final response = await h.client.get('/users?limit=1');

    expect(response.status, 200);
    expect(response.json, [
      {'id': 1, 'name': 'ann'},
    ]);
    expect((await h.client.get('/users')).json, hasLength(2));
  });

  test('finds one user; a filter maps a domain error to 404', () async {
    expect((await h.client.get('/users/2')).json, {'id': 2, 'name': 'bob'});

    final missing = await h.client.get('/users/9');
    expect(missing.status, 404);
    expect((missing.json as Map)['message'], 'No user 9');
  });
}

/// Creating users: status, location and guards.
void _writing(_Harness h) {
  test('POST by an admin creates a user: 201 with location', () async {
    final response = await h.client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer admin'},
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cid'});
  });

  test('guards: 401 without a token, 403 for a non-admin', () async {
    final anonymous = await h.client.post('/users', json: {'name': 'cid'});
    final guest = await h.client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer guest'},
    );

    expect(anonymous.status, 401);
    expect(anonymous.headers['www-authenticate'], 'Bearer');
    expect(guest.status, 403);
  });
}

/// Malformed or invalid input is a 400.
void _invalidInput(_Harness h) {
  test('malformed JSON, an invalid DTO and a bad int query are 400', () async {
    const admin = {'authorization': 'Bearer admin'};

    final malformed = await h.client.request(
      'POST',
      '/users',
      body: '{"name":',
      headers: admin,
    );
    final invalid = await h.client.post(
      '/users',
      json: {'name': ''},
      headers: admin,
    );
    final query = await h.client.get('/users?limit=ten');

    expect(malformed.status, 400);
    expect(invalid.status, 400);
    expect((invalid.json as Map)['message'], contains('"name"'));
    expect(query.status, 400);
  });
}

/// Tokens, bound interfaces, global modules and enum parameters.
void _wiring(_Harness h) {
  test('a token value, a bound interface and a global module', () async {
    final named = await h.client.get('/hello', headers: {'x-name': 'ann'});

    expect(named.json, {
      'greeting': 'Hello, ann!',
      'at': '1970-01-01T00:00:00.000Z',
    });
    expect(
      (await h.client.get('/hello')).json,
      containsPair('greeting', 'Hello, world!'),
    );
  });

  test('an enum path parameter, and a void handler is 204', () async {
    expect((await h.client.get('/status/banned')).json, {'status': 'banned'});
    expect((await h.client.get('/status/gone')).status, 400);
    expect((await h.client.delete('/hello')).status, 204);
  });
}

/// The router answers for the wrong method and an unknown path.
void _routing(_Harness h) {
  test('405 with allow, 404 for an unknown path, no errors', () async {
    final wrongMethod = await h.client.delete('/users');

    expect(wrongMethod.status, 405);
    expect(wrongMethod.headers['allow'], 'GET, HEAD, POST');
    expect((await h.client.get('/nope')).status, 404);
    expect(h.errors, isEmpty);
  });
}
