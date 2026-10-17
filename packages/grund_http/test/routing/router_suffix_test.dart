import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/routing/route_match.dart';
import 'package:test/test.dart';

import '../helpers/router_fixtures.dart';

void main() {
  group('Router suffix parameters', () {
    test('literal beats suffix beats parameter beats wildcard', () {
      final router = routerOf([
        ('GET', '/a/b.md'),
        ('GET', '/a/:x.md'),
        ('GET', '/a/:x'),
        ('GET', '/a/*'),
      ]);

      expect(match(router, 'GET', '/a/b.md'), found('GET /a/b.md'));
      expect(
        match(router, 'GET', '/a/c.md'),
        found('GET /a/:x.md', {'x': 'c'}),
      );
      expect(match(router, 'GET', '/a/c'), found('GET /a/:x', {'x': 'c'}));
      expect(match(router, 'GET', '/a/c/d'), found('GET /a/*', {'*': 'c/d'}));
    });

    test('the result does not depend on insertion order', () {
      final router = routerOf([
        ('GET', '/a/*'),
        ('GET', '/a/:x'),
        ('GET', '/a/:x.md'),
        ('GET', '/a/b.md'),
      ]);

      expect(match(router, 'GET', '/a/b.md'), found('GET /a/b.md'));
      expect(
        match(router, 'GET', '/a/c.md'),
        found('GET /a/:x.md', {'x': 'c'}),
      );
    });

    test('an empty stem does not match', () {
      final router = routerOf([('GET', '/a/:x.md'), ('GET', '/a/:x')]);

      expect(match(router, 'GET', '/a/.md'), found('GET /a/:x', {'x': '.md'}));
      expect(
        match(routerOf([('GET', '/a/:x.md')]), 'GET', '/a/.md'),
        isA<RouteNotFound<String>>(),
      );
    });

    test('the longer suffix is tried first', () {
      final router = routerOf([('GET', '/:n.gz'), ('GET', '/:n.tar.gz')]);

      expect(
        match(router, 'GET', '/x.tar.gz'),
        found('GET /:n.tar.gz', {'n': 'x'}),
      );
      expect(match(router, 'GET', '/x.gz'), found('GET /:n.gz', {'n': 'x'}));
    });

    test('falls back to a shorter suffix when the longer has no method', () {
      final router = routerOf([('GET', '/:n.gz'), ('POST', '/:n.tar.gz')]);

      expect(
        match(router, 'GET', '/x.tar.gz'),
        found('GET /:n.gz', {'n': 'x.tar'}),
      );
    });

    test('a segment with a decoded dot matches the suffix', () {
      final router = routerOf([('GET', '/:slug.md')]);

      expect(
        match(router, 'GET', '/grund.md'),
        found('GET /:slug.md', {'slug': 'grund'}),
      );
    });

    test('the suffix is case-sensitive', () {
      final router = routerOf([('GET', '/a/:x.md')]);

      expect(match(router, 'GET', '/a/x.MD'), isA<RouteNotFound<String>>());
    });

    test('a method missing on a suffix route answers 405 with Allow', () {
      final router = routerOf([('GET', '/a/:x.md')]);

      expect(
        match(router, 'DELETE', '/a/x.md'),
        isA<RouteMethodNotAllowed<String>>().having(
          (m) => m.allowed,
          'allowed',
          ['GET', 'HEAD'],
        ),
      );
    });

    test('HEAD falls back to GET of a suffix route', () {
      final router = routerOf([('GET', '/:slug.md')]);

      expect(
        match(router, 'HEAD', '/a.md'),
        found('GET /:slug.md', {'slug': 'a'}),
      );
    });

    test('a failing suffixed subtree falls through to a parameter', () {
      final router = routerOf([('GET', '/a/:x.md/c'), ('GET', '/a/:y/d')]);

      expect(
        match(router, 'GET', '/a/q.md/d'),
        found('GET /a/:y/d', {'y': 'q.md'}),
      );
    });

    test('a failing suffixed subtree falls through to a wildcard', () {
      final router = routerOf([('GET', '/a/:x.md/c'), ('GET', '/a/*')]);

      expect(
        match(router, 'GET', '/a/q.md/d'),
        found('GET /a/*', {'*': 'q.md/d'}),
      );
    });

    test('the same suffix with another name is a duplicate', () {
      expect(
        () => routerOf([('GET', '/a/:x.md'), ('GET', '/a/:y.md')]),
        throwsA(isA<DuplicateRouteError>()),
      );
    });

    test('different suffixes are different routes', () {
      final router = routerOf([('GET', '/a/:x.md'), ('GET', '/a/:x.json')]);

      expect(
        match(router, 'GET', '/a/q.json'),
        found('GET /a/:x.json', {'x': 'q'}),
      );
    });
  });
}
