import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

void main() {
  group('Container.create errors', () {
    test('missing provider reports module and chain', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => Service(i.get())),
          Provider((i) => Repo(i.get())),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', Clock)
              .having((e) => e.moduleId, 'moduleId', 'app')
              .having((e) => e.chain, 'chain', [Repo, Service]),
        ),
      );
    });

    test('circular dependency is detected', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => NeedsA(i.get())),
          Provider((i) => NeedsB(i.get())),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<CircularDependencyError>().having((e) => e.cycle, 'cycle', [
            NeedsA,
            NeedsB,
            NeedsA,
          ]),
        ),
      );
    });

    test('non-exported providers are invisible, with a hint', () async {
      final database = Module(
        id: 'database',
        providers: [Provider((i) => Secret()), Provider((i) => Db())],
        exports: [Db],
      );
      final app = Module(
        id: 'app',
        imports: [database],
        providers: [Provider((i) => UsesSecret(i.get()))],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', Secret)
              .having((e) => e.chain, 'chain', [UsesSecret])
              .having((e) => e.definedIn, 'definedIn', ['database']),
        ),
      );
    });

    test('async provider requested before creation fails clearly', () async {
      // UsesDb is created first (declaration order) and asks for Db, which
      // is async and still pending.
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => UsesDb(i.get())),
          Provider.async((i) async => Db()),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<AsyncProviderNotReadyError>()
              .having((e) => e.key, 'key', Db)
              .having((e) => e.chain, 'chain', [UsesDb]),
        ),
      );
    });

    test('plain async closure is guarded in sync get', () async {
      final tooEarly = Module(
        id: 'app',
        providers: [
          Provider((i) => UsesDb(i.get())),
          Provider((i) async => Db()),
        ],
      );
      await expectLater(
        Container.create(tooEarly),
        throwsA(
          isA<AsyncProviderNotReadyError>().having((e) => e.key, 'key', Db),
        ),
      );
    });

    test('maybeGet returns null for a missing provider', () async {
      final c = await Container.create(Module(id: 'app'));
      expect(c.root.maybeGet<Clock>(), isNull);
    });

    test(
      'maybeGet throws instead of returning null when the provider fails to create',
      () async {
        // Db is created first and probes Repo, whose factory needs a missing
        // Clock. The old swallow-all maybeGet let Db's factory continue.
        var reachedAfterProbe = false;
        final app = Module(
          id: 'app',
          providers: [
            Provider((i) {
              i.maybeGet<Repo>();
              reachedAfterProbe = true;
              return Db();
            }),
            Provider((i) => Repo(i.get())),
          ],
        );
        await expectLater(
          Container.create(app),
          throwsA(
            isA<MissingProviderError>().having((e) => e.key, 'key', Clock),
          ),
        );
        expect(
          reachedAfterProbe,
          isFalse,
          reason:
              'maybeGet must throw, not return null, for a provider that '
              'failed to create',
        );
      },
    );

    test('factory exception is wrapped with context', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider<Clock>((i) => throw StateError('boom')),
          Provider((i) => Repo(i.get())),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<ProviderCreationError>()
              .having((e) => e.key, 'key', Clock)
              .having((e) => e.moduleId, 'moduleId', 'app')
              .having((e) => e.error, 'error', isA<StateError>())
              .having((e) => e.chain, 'chain', isEmpty),
        ),
      );
    });

    test('get without type argument throws ArgumentError', () async {
      final c = await Container.create(
        Module(id: 'app', providers: [Provider((i) => Clock())]),
      );
      expect(() {
        Object value = c.root.get();
        return value;
      }, throwsArgumentError);
    });

    test('unknown module id', () async {
      final c = await Container.create(Module(id: 'app'));
      expect(() => c.injectorFor('nope'), throwsA(isA<UnknownModuleError>()));
    });

    test('structural errors surface before any factory runs', () async {
      var ran = false;
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) {
            ran = true;
            return Clock();
          }),
          Provider((i) => Clock()),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(isA<DuplicateProviderError>()),
      );
      expect(ran, isFalse);
    });

    test('global module non-exported provider is invisible', () async {
      final config = Module(
        id: 'config',
        global: true,
        providers: [Provider((i) => Secret()), Provider((i) => Config())],
        exports: [Config],
      );
      final app = Module(
        id: 'app',
        imports: [config],
        providers: [Provider((i) => UsesSecret(i.get()))],
      );
      await expectLater(
        Container.create(app),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', Secret)
              .having((e) => e.definedIn, 'definedIn', ['config']),
        ),
      );
    });

    test('async factory failure is wrapped with its cause', () async {
      final app = Module(
        id: 'app',
        providers: [Provider<Db>.async((i) async => throw StateError('boom'))],
      );
      await expectLater(
        Container.create(app),
        throwsA(
          isA<ProviderCreationError>()
              .having((e) => e.key, 'key', Db)
              .having((e) => e.error, 'error', isA<StateError>()),
        ),
      );
    });
  });
}
