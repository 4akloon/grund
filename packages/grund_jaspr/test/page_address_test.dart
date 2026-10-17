import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/page/page_address.dart';
import 'package:test/test.dart';

String _path(
  String pattern,
  Map<String, String> params,
  TrailingSlash policy,
) => PageAddress.pathOf(
  pattern,
  params,
  policy,
  pageSuffixes: JasprConfig.defaultPageSuffixes,
);

void main() {
  const never = TrailingSlash.never;

  test('encodes every segment and the values', () {
    expect(_path('/docs/:name', {'name': 'a b/c'}, never), '/docs/a%20b%2Fc');
  });

  test('the root is a slash under every policy', () {
    for (final policy in TrailingSlash.values) {
      expect(_path('/', const {}, policy), '/');
    }
  });

  test('always adds a slash unless the last segment has an extension', () {
    const always = TrailingSlash.always;
    expect(_path('/a', const {}, always), '/a/');
    expect(_path('/feed.xml', const {}, always), '/feed.xml');
    expect(_path('/p/:s', {'s': 'x.xml'}, always), '/p/x.xml');
  });

  test('a value that would be a file keeps its slash under every policy', () {
    for (final policy in TrailingSlash.values) {
      expect(_path('/p/:s', {'s': 'v1.2'}, policy), '/p/v1.2/');
    }
  });

  test('a page suffix is not a file', () {
    expect(_path('/p/:s', {'s': 'a.xml'}, never), '/p/a.xml');
    expect(_path('/p/:s', {'s': 'a.XML'}, never), '/p/a.XML');
  });

  test('an alternate path never gets the slash', () {
    expect(
      PageAddress.alternatePathOf('', '/p/:s', {'s': 'v1.2'}, '.md'),
      '/p/v1.2.md',
    );
  });

  for (final value in [null, '', '.', '..']) {
    test('rejects ${value == null ? 'a missing parameter' : '"$value"'}', () {
      expect(
        () => _path('/p/:slug', {'slug': ?value}, never),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('slug'),
          ),
        ),
      );
    });
  }
}
