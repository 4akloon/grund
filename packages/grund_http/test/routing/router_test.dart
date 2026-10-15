import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/routing/route_match.dart';
import 'package:grund_http/src/routing/route_pattern.dart';
import 'package:grund_http/src/routing/router.dart';
import 'package:test/test.dart';

Router<String> routerOf(List<(String, String)> routes) {
  final router = Router<String>();
  for (final (method, path) in routes) {
    router.add(
      method,
      RoutePattern.join('', path),
      '$method $path',
      source: '$method $path',
    );
  }
  return router;
}

List<String> split(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList();

RouteMatch<String> match(Router<String> router, String method, String path) =>
    router.match(method, split(path));

Matcher found(String value, [Map<String, String> parameters = const {}]) =>
    isA<RouteFound<String>>()
        .having((m) => m.value, 'value', value)
        .having((m) => m.parameters, 'parameters', parameters);

void main() {
  group('Router.match', () {
    test('static, parameter and root routes', () {
      final router = routerOf([
        ('GET', '/'),
        ('GET', '/users'),
        ('GET', '/users/:id'),
        ('GET', '/users/:id/posts/:postId'),
      ]);

      expect(match(router, 'GET', '/'), found('GET /'));
      expect(match(router, 'GET', '/users'), found('GET /users'));
      expect(
        match(router, 'GET', '/users/7'),
        found('GET /users/:id', {'id': '7'}),
      );
      expect(
        match(router, 'GET', '/users/7/posts/9'),
        found('GET /users/:id/posts/:postId', {'id': '7', 'postId': '9'}),
      );
    });

    test('static beats parameter beats wildcard', () {
      final router = routerOf([
        ('GET', '/files/readme'),
        ('GET', '/files/:name'),
        ('GET', '/files/*'),
      ]);

      expect(match(router, 'GET', '/files/readme'), found('GET /files/readme'));
      expect(
        match(router, 'GET', '/files/a'),
        found('GET /files/:name', {'name': 'a'}),
      );
      expect(
        match(router, 'GET', '/files/a/b/c'),
        found('GET /files/*', {'*': 'a/b/c'}),
      );
    });

    test('wildcard needs at least one segment', () {
      final router = routerOf([('GET', '/static/*')]);

      expect(match(router, 'GET', '/static'), isA<RouteNotFound<String>>());
    });

    // Review Focus 3: overlapping static and parameter routes.
    test('backtracks from a static branch to a parameter branch', () {
      final router = routerOf([
        ('GET', '/users/me'),
        ('GET', '/users/:id/posts'),
        ('DELETE', '/users/:id'),
      ]);

      expect(
        match(router, 'GET', '/users/me/posts'),
        found('GET /users/:id/posts', {'id': 'me'}),
      );
      expect(
        match(router, 'DELETE', '/users/me'),
        found('DELETE /users/:id', {'id': 'me'}),
      );
      expect(match(router, 'GET', '/users/me'), found('GET /users/me'));
    });

    test('unknown path is not found', () {
      final router = routerOf([('GET', '/users')]);

      expect(match(router, 'GET', '/posts'), isA<RouteNotFound<String>>());
      expect(match(router, 'GET', '/users/1'), isA<RouteNotFound<String>>());
    });

    test('known path with another method is 405 with sorted methods', () {
      final router = routerOf([
        ('POST', '/users/:id'),
        ('GET', '/users/me'),
        ('PUT', '/users/:id'),
      ]);

      expect(
        match(router, 'PATCH', '/users/me'),
        isA<RouteMethodNotAllowed<String>>().having(
          (m) => m.allowed,
          'allowed',
          ['GET', 'HEAD', 'POST', 'PUT'],
        ),
      );
    });

    test('HEAD falls back to GET, an explicit HEAD wins', () {
      final router = routerOf([('GET', '/a'), ('GET', '/b'), ('HEAD', '/b')]);

      expect(match(router, 'HEAD', '/a'), found('GET /a'));
      expect(match(router, 'HEAD', '/b'), found('HEAD /b'));
    });

    test('methods are case-insensitive', () {
      final router = routerOf([('get', '/a')]);

      expect(match(router, 'GET', '/a'), found('get /a'));
    });

    test('result does not depend on insertion order', () {
      final routes = [('GET', '/x/:id'), ('GET', '/x/new'), ('GET', '/x/*')];
      final forward = routerOf(routes);
      final backward = routerOf(routes.reversed.toList());

      for (final path in ['/x/new', '/x/7', '/x/7/8']) {
        final a = match(forward, 'GET', path) as RouteFound<String>;
        final b = match(backward, 'GET', path) as RouteFound<String>;
        expect(a.value, b.value, reason: path);
      }
    });
  });

  group('Router.add', () {
    test('same method and shape is a duplicate even with other names', () {
      final router = Router<String>()
        ..add('GET', RoutePattern.join('/users', ':id'), 'a', source: 'A.one');

      expect(
        () => router.add(
          'get',
          RoutePattern.join('/users', ':userId'),
          'b',
          source: 'B.two',
        ),
        throwsA(
          isA<DuplicateRouteError>()
              .having((e) => e.method, 'method', 'GET')
              .having((e) => e.path, 'path', '/users/:userId')
              .having((e) => e.existing, 'existing', 'A.one')
              .having((e) => e.duplicate, 'duplicate', 'B.two'),
        ),
      );
    });

    test('same path with another method is not a duplicate', () {
      final router = routerOf([('GET', '/a'), ('POST', '/a')]);

      expect(match(router, 'POST', '/a'), found('POST /a'));
    });
  });
}
