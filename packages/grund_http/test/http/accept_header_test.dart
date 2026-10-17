import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

void main() {
  group('absent header', () {
    for (final value in <String?>[null, '', '  ']) {
      test('${value == null ? 'null' : "'$value'"} accepts everything', () {
        final accept = AcceptHeader.parse(value);

        expect(accept.qualityOf('text/markdown'), 1);
        expect(accept.qualityOf('anything/else'), 1);
        expect(accept.names('text/markdown'), isFalse);
      });
    }
  });

  group('qualities', () {
    test('a named type has quality 1 and is named', () {
      final accept = AcceptHeader.parse('text/markdown');

      expect(accept.qualityOf('text/markdown'), 1);
      expect(accept.names('text/markdown'), isTrue);
      expect(accept.qualityOf('text/html'), 0);
    });

    test('reads q', () {
      expect(
        AcceptHeader.parse('text/markdown;q=0.5').qualityOf('text/markdown'),
        0.5,
      );
    });

    test('the parameter name is case-insensitive', () {
      expect(
        AcceptHeader.parse('text/markdown;Q=0.5').qualityOf('text/markdown'),
        0.5,
      );
    });

    for (final bad in ['1.0001', 'abc', '-1', '2', '.5', 'Infinity']) {
      test('q=$bad is 0 and never names the type', () {
        final accept = AcceptHeader.parse('text/markdown;q=$bad');

        expect(accept.qualityOf('text/markdown'), 0);
        expect(accept.names('text/markdown'), isFalse);
      });
    }

    test('other parameters are ignored', () {
      final accept = AcceptHeader.parse('text/markdown;charset=utf-8');

      expect(accept.qualityOf('text/markdown'), 1);
    });

    test('a repeated range takes the highest quality', () {
      final accept = AcceptHeader.parse('text/html;q=0.2, text/html;q=0.9');

      expect(accept.qualityOf('text/html'), 0.9);
    });

    test('a repeated range takes the highest quality in any order', () {
      final accept = AcceptHeader.parse('text/html;q=0.9, text/html;q=0.2');

      expect(accept.qualityOf('text/html'), 0.9);
    });

    for (final (weight, expected) in [
      ('0', 0.0),
      ('1', 1.0),
      ('0.001', 0.001),
      ('1.000', 1.0),
    ]) {
      test('q=$weight is accepted as $expected', () {
        final accept = AcceptHeader.parse('text/markdown;q=$weight');

        expect(accept.qualityOf('text/markdown'), expected);
      });
    }

    test('names matches case-insensitively', () {
      expect(
        AcceptHeader.parse('text/markdown').names('TEXT/Markdown'),
        isTrue,
      );
    });

    test('media types match case-insensitively', () {
      final accept = AcceptHeader.parse('TEXT/Markdown');

      expect(accept.qualityOf('text/markdown'), 1);
      expect(accept.qualityOf('TEXT/MARKDOWN'), 1);
    });
  });

  group('wildcards', () {
    test('type/* gives its quality but does not name the type', () {
      final accept = AcceptHeader.parse('text/*;q=0.3');

      expect(accept.qualityOf('text/markdown'), 0.3);
      expect(accept.names('text/markdown'), isFalse);
      expect(accept.qualityOf('image/png'), 0);
    });

    test('*/* gives 1 to everything without naming it', () {
      final accept = AcceptHeader.parse('*/*');

      expect(accept.qualityOf('text/markdown'), 1);
      expect(accept.names('text/markdown'), isFalse);
    });

    test('the exact range beats type/* beats */* in any order', () {
      for (final value in [
        '*/*;q=0.1, text/*;q=0.2, text/markdown;q=0.3',
        'text/markdown;q=0.3, text/*;q=0.2, */*;q=0.1',
        'text/*;q=0.2, text/markdown;q=0.3, */*;q=0.1',
      ]) {
        final accept = AcceptHeader.parse(value);

        expect(accept.qualityOf('text/markdown'), 0.3, reason: value);
        expect(accept.qualityOf('text/html'), 0.2, reason: value);
        expect(accept.qualityOf('image/png'), 0.1, reason: value);
      }
    });

    test('an exact range with q=0 excludes the type despite */*', () {
      final accept = AcceptHeader.parse('text/markdown;q=0, */*');

      expect(accept.qualityOf('text/markdown'), 0);
      expect(accept.names('text/markdown'), isFalse);
    });
  });

  group('malformed input', () {
    test('garbage yields 0 for everything', () {
      final accept = AcceptHeader.parse(',,;;,q=');

      expect(accept.qualityOf('text/html'), 0);
      expect(accept.names('text/html'), isFalse);
    });

    test('*/x is skipped', () {
      final accept = AcceptHeader.parse('*/x, text/html');

      expect(accept.qualityOf('image/png'), 0);
      expect(accept.qualityOf('text/html'), 1);
    });
  });
}
