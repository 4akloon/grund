import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

abstract class Ticker {}

class SystemTicker implements Ticker {}

class Repo {
  Repo(this.clock);
  final Clock clock;
}

/// Minimal injector double: returns pre-registered instances by key.
class FakeInjector implements Injector {
  FakeInjector(this.values);
  final Map<Object, Object> values;

  @override
  String get moduleId => 'fake';

  @override
  T get<T extends Object>([Token<T>? token]) => values[token ?? T] as T;

  @override
  T? maybeGet<T extends Object>([Token<T>? token]) => values[token ?? T] as T?;
}

void main() {
  group('Provider', () {
    test('infers T from the factory return type and keys by Type', () {
      final provider = Provider((i) => Clock());
      expect(provider.type, Clock);
      expect(provider.key, Clock);
      expect(provider.isAsync, isFalse);
    });

    test('infers i.get() type from the constructor parameter', () {
      final clock = Clock();
      final provider = Provider((i) => Repo(i.get()));
      final repo = provider.create(FakeInjector({Clock: clock})) as Repo;
      expect(repo.clock, same(clock));
    });

    test('uses the token as key when given', () {
      const dbUrl = Token<String>('db.url');
      final provider = Provider.value('postgres://x', token: dbUrl);
      expect(provider.key, dbUrl);
      expect(provider.create(FakeInjector({})), 'postgres://x');
    });

    test(
      'explicit type parameter binds an abstraction to an implementation',
      () {
        final provider = Provider<Ticker>((i) => SystemTicker());
        expect(provider.key, Ticker);
        expect(provider.type, Ticker);
      },
    );

    test('rejects a type parameter that could not be inferred', () {
      expect(() => Provider<Object>((i) => Clock()), throwsArgumentError);
    });

    test('Provider.async is flagged and returns a Future', () async {
      final provider = Provider.async((i) async => Clock());
      expect(provider.isAsync, isTrue);
      expect(provider.type, Clock);
      expect(await provider.create(FakeInjector({})), isA<Clock>());
    });

    test('a plain async closure infers T through FutureOr', () {
      final provider = Provider((i) async => Clock());
      expect(provider.type, Clock);
      expect(provider.isAsync, isFalse);
      expect(provider.create(FakeInjector({})), isA<Future<Clock>>());
    });

    test('toString names the type and token', () {
      expect(Provider((i) => Clock()).toString(), 'Provider<Clock>');
      expect(
        Provider.value(1, token: const Token<int>('port')).toString(),
        'Provider<int>(Token<int>(port))',
      );
    });
  });
}
