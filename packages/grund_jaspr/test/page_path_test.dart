import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/page/page_path.dart';
import 'package:test/test.dart';

void main() {
  group('PagePath.parse', () {
    test('reads parameter names', () {
      final path = PagePath.parse('/projects/:slug');
      expect(path.paramNames, ['slug']);
      expect(path.hasParams, isTrue);
      expect(path.normalized, '/projects/:slug');
    });

    test('normalizes the root', () {
      final path = PagePath.parse('/');
      expect(path.normalized, '/');
      expect(path.hasParams, isFalse);
      expect(path.paramNames, isEmpty);
    });

    for (final bad in ['users', '/a/*', '/a-:id', '/a/:', '/a//b']) {
      test('rejects "$bad"', () {
        expect(
          () => PagePath.parse(bad),
          throwsA(
            isA<InvalidPagePathError>()
                .having((e) => e.path, 'path', bad)
                .having((e) => e.message, 'message', contains(bad)),
          ),
        );
      });
    }
  });

  group('PagePath.checkSitePath', () {
    test('accepts the empty path and literal segments', () {
      PagePath.checkSitePath('');
      PagePath.checkSitePath('/admin');
      PagePath.checkSitePath('/a/b');
    });

    for (final bad in ['/admin/', 'admin', '/a/:b', '/a/*', '/a//b']) {
      test('rejects "$bad"', () {
        expect(
          () => PagePath.checkSitePath(bad),
          throwsA(isA<InvalidSitePathError>()),
        );
      });
    }
  });
}
