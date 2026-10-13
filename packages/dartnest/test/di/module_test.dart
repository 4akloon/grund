import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

void main() {
  group('Module', () {
    test('has sensible defaults', () {
      final m = Module(id: 'app');
      expect(m.id, 'app');
      expect(m.imports, isEmpty);
      expect(m.providers, isEmpty);
      expect(m.exports, isEmpty);
      expect(m.global, isFalse);
    });

    test('dynamic modules are plain functions returning a Module', () {
      Module database({required String url}) => Module(
        id: 'database',
        providers: [
          Provider<String>.value(url, token: const Token<String>('db.url')),
        ],
        exports: [const Token<String>('db.url')],
      );
      final m = database(url: 'postgres://x');
      expect(m.providers.single.key, const Token<String>('db.url'));
    });

    test('toString shows the id', () {
      expect(Module(id: 'users').toString(), 'Module(users)');
    });
  });

  group('errors', () {
    test('MissingProviderError message contains chain and hint', () {
      final e = MissingProviderError(
        key: Clock,
        moduleId: 'users',
        chain: [Clock, String],
        definedIn: ['core'],
      );
      expect(e.message, contains('No provider for Clock in module "users"'));
      expect(e.message, contains('Clock <- String'));
      expect(e.message, contains('declared in module(s) [core]'));
      expect(e.toString(), startsWith('MissingProviderError: '));
    });

    test('CircularDependencyError lists the cycle', () {
      final e = CircularDependencyError([Clock, String, Clock]);
      expect(e.message, contains('Clock -> String -> Clock'));
    });

    test('describeKey formats types and tokens', () {
      expect(describeKey(Clock), 'Clock');
      expect(describeKey(const Token<int>('port')), 'Token<int>(port)');
    });

    test('errors are Exceptions under the sealed roots', () {
      expect(const DuplicateModuleIdError('x'), isA<InjectionError>());
      expect(const DuplicateModuleIdError('x'), isA<DartnestError>());
      expect(const DuplicateModuleIdError('x'), isA<Exception>());
    });
  });
}
