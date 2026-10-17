import 'package:grund/grund.dart';
import 'package:test/test.dart';

Environment env(Map<String, String> values) => Environment(values);

void main() {
  group('Environment.has', () {
    test('counts an empty value as set', () {
      expect(env({'A': ''}).has('A'), isTrue);
      expect(env({}).has('A'), isFalse);
    });
  });

  group('Environment.string', () {
    test('returns the value, also an empty one, ignoring the fallback', () {
      expect(env({'A': 'x'}).string('A', fallback: 'y'), 'x');
      expect(env({'A': ''}).string('A', fallback: 'y'), '');
    });

    test('returns the fallback only when unset', () {
      expect(env({}).string('A', fallback: 'y'), 'y');
    });

    test('throws MissingVariableError when unset without a fallback', () {
      expect(
        () => env({}).string('A'),
        throwsA(isA<MissingVariableError>().having((e) => e.name, 'name', 'A')),
      );
    });
  });

  group('Environment.integer', () {
    test('parses decimal integers, leading zeros and negatives', () {
      expect(env({'N': '80'}).integer('N'), 80);
      expect(env({'N': '007'}).integer('N'), 7);
      expect(env({'N': '-5'}).integer('N'), -5);
    });

    test('returns the fallback only when unset, unchecked by the range', () {
      expect(env({}).integer('N', fallback: 99, min: 0, max: 10), 99);
    });

    test('throws MissingVariableError when unset without a fallback', () {
      expect(() => env({}).integer('N'), throwsA(isA<MissingVariableError>()));
    });

    for (final bad in [
      ' 80',
      '80 ',
      '+80',
      '0x50',
      '1e3',
      '1.5',
      '',
      '-',
      '8\n',
      '99999999999999999999',
    ]) {
      test('rejects ${bad.isEmpty ? 'an empty value' : "'$bad'"} instead of '
          'falling back', () {
        expect(
          () => env({'N': bad}).integer('N', fallback: 1),
          throwsA(
            isA<InvalidVariableError>()
                .having((e) => e.name, 'name', 'N')
                .having((e) => e.expected, 'expected', 'an integer'),
          ),
        );
      });
    }

    test('accepts the bounds and rejects values outside them', () {
      expect(env({'N': '0'}).integer('N', min: 0, max: 5), 0);
      expect(env({'N': '5'}).integer('N', min: 0, max: 5), 5);
      expect(
        () => env({'N': '6'}).integer('N', min: 0, max: 5),
        throwsA(isA<InvalidVariableError>()),
      );
      expect(
        () => env({'N': '-1'}).integer('N', min: 0, max: 5),
        throwsA(isA<InvalidVariableError>()),
      );
    });

    test('phrases the expectation after the bounds that are given', () {
      String expected({int? min, int? max, String value = 'x'}) {
        try {
          env({'N': value}).integer('N', min: min, max: max);
        } on InvalidVariableError catch (e) {
          return e.expected;
        }
        throw StateError('no error');
      }

      expect(expected(min: 0, max: 65535), 'an integer from 0 to 65535');
      expect(expected(min: 1), 'an integer of at least 1');
      expect(expected(max: 9), 'an integer of at most 9');
      expect(expected(), 'an integer');
      expect(expected(min: 0, max: 5, value: '6'), 'an integer from 0 to 5');
      expect(expected(min: 1, value: '0'), 'an integer of at least 1');
      expect(expected(max: 9, value: '10'), 'an integer of at most 9');
    });
  });

  group('environment errors', () {
    test('MissingVariableError names the variable', () {
      expect(
        const MissingVariableError('PORT').message,
        'The environment variable PORT is not set. Set it, or read it with a '
        'fallback.',
      );
    });

    test('InvalidVariableError message is exact', () {
      expect(
        const InvalidVariableError(
          name: 'PORT',
          expected: 'an integer from 0 to 65535',
        ).message,
        'The environment variable PORT must be an integer from 0 to 65535. '
        'Its value is not shown, as it may be a secret.',
      );
    });

    test('never show the value, in message or toString', () {
      expect(
        () => env({'SECRET': 'hunter2'}).integer('SECRET'),
        throwsA(
          isA<InvalidVariableError>()
              .having((e) => e.message, 'message', isNot(contains('hunter2')))
              .having((e) => '$e', 'toString', isNot(contains('hunter2'))),
        ),
      );

      expect(
        const MissingVariableError('SECRET').toString(),
        contains('SECRET'),
      );
    });
  });
}
