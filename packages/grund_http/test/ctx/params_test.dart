import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

enum Color { red, green }

Params queryOf(Map<String, List<String>> values) =>
    Params(ParamLocation.query, (name) => values[name] ?? const []);

Matcher badRequest(String code, String pointer) => isA<BadRequestException>()
    .having((e) => e.code, 'code', code)
    .having((e) => e.pointer, 'pointer', pointer);

void main() {
  group('Params reading', () {
    test('converts every built-in type', () {
      final params = queryOf({
        'name': ['ann'],
        'page': ['3'],
        'price': ['2.5'],
        'done': ['true'],
        'at': ['2026-10-15T10:00:00Z'],
        'next': ['https://example.com/a?b=1'],
        'color': ['green'],
      });

      expect(params.string('name'), 'ann');
      expect(params.integer('page'), 3);
      expect(params.decimal('price'), 2.5);
      expect(params.boolean('done'), isTrue);
      expect(params.dateTime('at'), DateTime.utc(2026, 10, 15, 10));
      expect(params.uri('next').host, 'example.com');
      expect(params.enumOf('color', Color.values), Color.green);
    });

    test('the OrNull readers return null for an absent parameter', () {
      final params = queryOf({});

      expect(params.stringOrNull('a'), isNull);
      expect(params.integerOrNull('a'), isNull);
      expect(params.decimalOrNull('a'), isNull);
      expect(params.booleanOrNull('a'), isNull);
      expect(params.dateTimeOrNull('a'), isNull);
      expect(params.uriOrNull('a'), isNull);
      expect(params.enumOfOrNull('a', Color.values), isNull);
    });

    test('a repeated parameter reads as the first value, all has all', () {
      final params = queryOf({
        'tag': ['a', 'b'],
      });

      expect(params.string('tag'), 'a');
      expect(params.all('tag'), ['a', 'b']);
      expect(params.all('none'), isEmpty);
    });

    test('an empty value is a value', () {
      final params = queryOf({
        'q': [''],
      });

      expect(params.string('q'), '');
      expect(() => params.integer('q'), throwsA(isA<BadRequestException>()));
    });
  });

  group('Params errors (RF-3)', () {
    test('an absent required parameter is parameter_missing', () {
      expect(
        () => queryOf({}).integer('page'),
        throwsA(badRequest('parameter_missing', '/query/page')),
      );
    });

    test('the pointer names the location', () {
      final header = Params(ParamLocation.header, (_) => const []);
      final path = Params(ParamLocation.path, (_) => const []);

      expect(
        () => header.string('x-key'),
        throwsA(badRequest('parameter_missing', '/header/x-key')),
      );
      expect(
        () => path.integer('id'),
        throwsA(badRequest('parameter_missing', '/path/id')),
      );
    });

    test('values of the wrong type are parameter_invalid', () {
      for (final read in <(String, Object? Function(Params))>[
        ('abc', (p) => p.integer('v')),
        ('1.5', (p) => p.integer('v')),
        ('0x10', (p) => p.integer('v')),
        ('99999999999999999999', (p) => p.integer('v')),
        ('1e', (p) => p.decimal('v')),
        ('NaN', (p) => p.decimal('v')),
        ('yes', (p) => p.boolean('v')),
        ('tomorrow', (p) => p.dateTime('v')),
        ('', (p) => p.uri('v')),
        ('blue', (p) => p.enumOf('v', Color.values)),
      ]) {
        final params = queryOf({
          'v': [read.$1],
        });
        expect(
          () => read.$2(params),
          throwsA(badRequest('parameter_invalid', '/query/v')),
          reason: 'value "${read.$1}"',
        );
      }
    });

    test('an invalid OrNull value is still rejected', () {
      final params = queryOf({
        'page': ['x'],
      });

      expect(
        () => params.integerOrNull('page'),
        throwsA(badRequest('parameter_invalid', '/query/page')),
      );
    });

    test('a long value is shortened in the message', () {
      final params = queryOf({
        'v': ['x' * 500],
      });

      expect(
        () => params.integer('v'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.message.length,
            'message length',
            lessThan(200),
          ),
        ),
      );
    });
  });

  group('Params constraints', () {
    test('integer and decimal bounds are inclusive', () {
      final params = queryOf({
        'a': ['1'],
        'b': ['100'],
        'c': ['0'],
        'd': ['101'],
        'x': ['0.5'],
      });

      expect(params.integer('a', min: 1, max: 100), 1);
      expect(params.integer('b', min: 1, max: 100), 100);
      expect(
        () => params.integer('c', min: 1),
        throwsA(badRequest('parameter_out_of_range', '/query/c')),
      );
      expect(
        () => params.integer('d', max: 100),
        throwsA(badRequest('parameter_out_of_range', '/query/d')),
      );
      expect(
        () => params.decimal('x', min: 1),
        throwsA(badRequest('parameter_out_of_range', '/query/x')),
      );
    });

    test('string length is checked in characters', () {
      final params = queryOf({
        's': ['abc'],
      });

      expect(params.string('s', minLength: 3, maxLength: 3), 'abc');
      expect(
        () => params.string('s', minLength: 4),
        throwsA(badRequest('parameter_out_of_range', '/query/s')),
      );
      expect(
        () => params.string('s', maxLength: 2),
        throwsA(badRequest('parameter_out_of_range', '/query/s')),
      );
    });

    test('a pattern must match the whole value', () {
      final params = queryOf({
        'ok': ['ab12'],
        'partial': ['ab12!'],
      });

      expect(params.string('ok', pattern: r'[a-z]+\d+'), 'ab12');
      expect(
        () => params.string('partial', pattern: r'[a-z]+\d+'),
        throwsA(badRequest('parameter_invalid', '/query/partial')),
      );
    });

    test('oneOf accepts only the listed values', () {
      final params = queryOf({
        'sort': ['name'],
        'bad': ['id'],
      });

      expect(params.string('sort', oneOf: ['name', 'date']), 'name');
      expect(
        () => params.string('bad', oneOf: ['name', 'date']),
        throwsA(badRequest('parameter_invalid', '/query/bad')),
      );
    });
  });
}
