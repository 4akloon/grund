import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/page/page_address.dart';
import 'package:test/test.dart';

void main() {
  const never = TrailingSlash.never;

  test('encodes every segment and the values', () {
    expect(
      PageAddress.pathOf('/docs/:name', {'name': 'a b/c'}, never),
      '/docs/a%20b%2Fc',
    );
  });

  test('the root is a slash under every policy', () {
    for (final policy in TrailingSlash.values) {
      expect(PageAddress.pathOf('/', const {}, policy), '/');
    }
  });

  test('always adds a slash unless the last segment has an extension', () {
    const always = TrailingSlash.always;
    expect(PageAddress.pathOf('/a', const {}, always), '/a/');
    expect(PageAddress.pathOf('/feed.xml', const {}, always), '/feed.xml');
    expect(PageAddress.pathOf('/p/:s', {'s': 'x.y'}, always), '/p/x.y');
  });

  for (final value in [null, '', '.', '..']) {
    test('rejects ${value == null ? 'a missing parameter' : '"$value"'}', () {
      expect(
        () => PageAddress.pathOf('/p/:slug', {'slug': ?value}, never),
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
