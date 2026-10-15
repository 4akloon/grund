import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('HeaderMap', () {
    test('lookups ignore the case of the name', () {
      final headers = HeaderMap.of({'Content-Type': 'application/json'});

      expect(headers['content-type'], 'application/json');
      expect(headers['CONTENT-TYPE'], 'application/json');
      expect(headers.contains('Content-type'), isTrue);
      expect(headers.names, ['content-type']);
    });

    test('add keeps every value of a name in order', () {
      final headers = HeaderMap()
        ..add('Set-Cookie', 'a=1')
        ..add('set-cookie', 'b=2');

      expect(headers.all('SET-COOKIE'), ['a=1', 'b=2']);
      expect(headers['set-cookie'], 'a=1');
    });

    test('set replaces, remove deletes, absent names read as empty', () {
      final headers = HeaderMap()
        ..add('x-a', '1')
        ..add('x-a', '2')
        ..set('X-A', '3');
      expect(headers.all('x-a'), ['3']);

      headers.remove('x-A');
      expect(headers['x-a'], isNull);
      expect(headers.all('x-a'), isEmpty);
    });

    test('setAll overrides only the names present in the other map', () {
      final headers = HeaderMap.of({'a': '1', 'b': '2'})
        ..setAll(HeaderMap.of({'B': '3', 'c': '4'}));

      expect(headers.toMap(), {
        'a': ['1'],
        'b': ['3'],
        'c': ['4'],
      });
    });

    test('unmodifiable copies reject changes and do not track the source', () {
      final source = HeaderMap.of({'a': '1'});
      final frozen = HeaderMap.unmodifiable(source);
      source.add('a', '2');

      expect(frozen.isReadOnly, isTrue);
      expect(frozen.all('a'), ['1']);
      expect(() => frozen.add('a', '3'), throwsUnsupportedError);
      expect(() => frozen.set('a', '3'), throwsUnsupportedError);
      expect(() => frozen.remove('a'), throwsUnsupportedError);
      expect(HeaderMap.copy(frozen).isReadOnly, isFalse);
    });
  });
}
