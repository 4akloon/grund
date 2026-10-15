import 'package:grund/grund.dart' show GrundError;
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/routing/pattern_segment.dart';
import 'package:grund_http/src/routing/route_pattern.dart';
import 'package:test/test.dart';

Matcher invalidPattern(String pattern, String reasonPart) => throwsA(
  isA<InvalidRoutePatternError>()
      .having((e) => e.pattern, 'pattern', pattern)
      .having((e) => e.reason, 'reason', contains(reasonPart)),
);

void main() {
  group('RoutePattern.join', () {
    test('joins prefix and path and normalizes slashes', () {
      expect(RoutePattern.join('/users', '/:id').toString(), '/users/:id');
      expect(RoutePattern.join('users/', 'posts/').toString(), '/users/posts');
      expect(RoutePattern.join('', '//a//b').toString(), '/a/b');
      expect(RoutePattern.join('', '/').toString(), '/');
      expect(RoutePattern.join('', '').segments, isEmpty);
    });

    test('classifies segments', () {
      final pattern = RoutePattern.join('/files', ':owner/*');

      expect(pattern.segments, [
        isA<StaticSegment>().having((s) => s.value, 'value', 'files'),
        isA<ParamSegment>().having((s) => s.name, 'name', 'owner'),
        isA<WildcardSegment>(),
      ]);
      expect(pattern.parameterNames, ['owner', '*']);
    });

    test('wildcard must be last', () {
      expect(
        () => RoutePattern.join('/files/*', '/:id'),
        invalidPattern('/files/*/:id', 'must be the last segment'),
      );
    });

    test('parameter names must be identifiers', () {
      expect(
        () => RoutePattern.join('', '/:'),
        invalidPattern('/:', 'parameter name ""'),
      );
      expect(
        () => RoutePattern.join('', '/:user-id'),
        invalidPattern('/:user-id', 'parameter name "user-id"'),
      );
    });

    test('partial parameters and wildcards are rejected', () {
      expect(
        () => RoutePattern.join('', '/file.*'),
        invalidPattern('/file.*', 'mixes literal text'),
      );
      expect(
        () => RoutePattern.join('', '/a:b'),
        invalidPattern('/a:b', 'mixes literal text'),
      );
    });

    test('a parameter name may appear only once', () {
      expect(
        () => RoutePattern.join('/users/:id', '/posts/:id'),
        invalidPattern('/users/:id/posts/:id', 'appears twice'),
      );
    });
  });

  group('DuplicateRouteError', () {
    test('names both handlers', () {
      const error = DuplicateRouteError(
        method: 'GET',
        path: '/users/:id',
        existing: 'A.one (module "a")',
        duplicate: 'B.two (module "b")',
      );

      expect(
        error.message,
        'Route GET /users/:id is declared twice: by A.one (module "a") and by '
        'B.two (module "b"). Parameter names do not distinguish routes.',
      );
      expect(error, isA<GrundError>());
    });
  });
}
