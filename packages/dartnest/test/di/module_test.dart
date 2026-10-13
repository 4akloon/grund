import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

class Clock2 {}

class Db {}

abstract interface class Ticker {}

class SystemTicker implements Ticker {}

final class ExternalError extends DartnestError {
  const ExternalError();

  @override
  String get message => 'boom';
}

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
        providers: [Provider.value(url, token: const Token<String>('db.url'))],
        exports: [const Token<String>('db.url')],
      );
      final m = database(url: 'postgres://x');
      expect(m.providers.single.key, const Token<String>('db.url'));
    });

    test('providers written in a Module list infer their own types', () {
      final m = Module(
        id: 'a',
        providers: [
          Provider((i) => Clock()),
          Provider.value('x', token: const Token<String>('s')),
          Provider.value(5, token: const Token<int>('n')),
          Provider.async((i) async => Db()),
          Provider((i) async => Clock2()),
          Provider<Ticker>((i) => SystemTicker()),
        ],
      );
      expect(m.providers.map((p) => p.key).toList(), [
        Clock,
        const Token<String>('s'),
        const Token<int>('n'),
        Db,
        Clock2,
        Ticker,
      ]);
      expect(m.providers.map((p) => p.isAsync).toList(), [
        false,
        false,
        false,
        true,
        false,
        false,
      ]);
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

    test(
      'errors are Exceptions: InjectionError is sealed, DartnestError is open',
      () {
        expect(const DuplicateModuleIdError('x'), isA<InjectionError>());
        expect(const DuplicateModuleIdError('x'), isA<DartnestError>());
        expect(const DuplicateModuleIdError('x'), isA<Exception>());
      },
    );

    test('DartnestError can be extended from another library', () {
      Object caught = '';
      try {
        throw const ExternalError();
      } on DartnestError catch (e) {
        caught = e;
      }
      expect(caught, isA<ExternalError>());
      expect(caught.toString(), 'ExternalError: boom');
    });
  });
}
