import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('Runners.fromArgs', () {
    test('is null without the flag, which means "start everything"', () {
      expect(Runners.fromArgs(const ['serve', '--verbose']), isNull);
    });

    test('reads a comma separated list after =', () {
      expect(Runners.fromArgs(const ['--only=http,jobs']), {'http', 'jobs'});
    });

    test('reads the list from the next argument', () {
      expect(Runners.fromArgs(const ['--only', 'http']), {'http'});
    });

    test('trims names and ignores empty ones', () {
      expect(Runners.fromArgs(const ['--only= http ,,jobs,']), {
        'http',
        'jobs',
      });
    });

    test('an empty list selects nothing', () {
      expect(Runners.fromArgs(const ['--only=']), isEmpty);
      expect(Runners.fromArgs(const ['--only']), isEmpty);
    });
  });
}
