import 'package:grund_http/grund_http.dart';

import 'conformance_users.dart';

/// `GET /users/:id` and `POST /users` (`{"name"}` answers 201 with a
/// `location` header).
final class UsersApi extends HttpApi {
  /// Creates the API over [_users].
  UsersApi(super.injector, this._users);

  final ConformanceUsers _users;

  @override
  String get path => '/users';

  @override
  List<Route> get routes => [
    Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
    Route.post('/', _create, status: StatusCode.created),
  ];

  Future<Map<String, Object?>> _create(HttpCtx c) async {
    final name = await c.body(
      (json) => switch (json) {
        {'name': final String name} => name,
        _ => throw const FormatException('"name" must be a string'),
      },
    );
    final user = _users.create(name);
    c.response.headers.set('location', '/users/${user['id']}');
    return user;
  }
}
