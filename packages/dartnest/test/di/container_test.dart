import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

class Repo {
  Repo(this.clock);
  final Clock clock;
}

class Service {
  Service(this.repo);
  final Repo repo;
}

class Db {}

class Secret {}

class Config {}

class UsesSecret {
  UsesSecret(Secret secret);
}

class UsesDb {
  UsesDb(Db db);
}

class NeedsA {
  NeedsA(NeedsB b);
}

class NeedsB {
  NeedsB(NeedsA a);
}

void main() {
  group('Container.create', () {
    test('resolves sync providers regardless of declaration order', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => Service(i.get())),
          Provider((i) => Repo(i.get())),
          Provider((i) => Clock()),
        ],
      );

      final c = await Container.create(app);

      final service = c.root.get<Service>();
      expect(service.repo.clock, same(c.root.get<Clock>()));
      expect(c.root.moduleId, 'app');
    });

    test('providers are singletons created exactly once', () async {
      var created = 0;
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created++;
            return Clock();
          }),
          Provider((i) => Repo(i.get())),
          Provider((i) => Service(i.get())),
        ],
      );

      final c = await Container.create(app);
      c.root.get<Clock>();
      c.root.get<Service>();

      expect(created, 1);
      expect(c.root.get<Clock>(), same(c.root.get<Repo>().clock));
    });

    test('token providers resolve by token', () async {
      const url = Token<String>('db.url');
      final c = await Container.create(
        Module(
          id: 'app',
          providers: [Provider.value('pg://x', token: url)],
        ),
      );
      expect(c.root.get(url), 'pg://x');
      expect(c.root.maybeGet<String>(), isNull);
    });

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

    test('exports of imported modules are visible', () async {
      final database = Module(
        id: 'database',
        providers: [Provider((i) => Db())],
        exports: [Db],
      );
      final app = Module(
        id: 'app',
        imports: [database],
        providers: [Provider((i) => UsesDb(i.get()))],
      );

      final c = await Container.create(app);

      expect(c.root.get<Db>(), same(c.injectorFor('database').get<Db>()));
      expect(c.root.get<UsesDb>(), isA<UsesDb>());
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

    test('re-exported modules pass their exports through', () async {
      final database = Module(
        id: 'database',
        providers: [Provider((i) => Db())],
        exports: [Db],
      );
      final shared = Module(
        id: 'shared',
        imports: [database],
        exports: [database],
      );
      final app = Module(
        id: 'app',
        imports: [shared],
        providers: [Provider((i) => UsesDb(i.get()))],
      );

      final c = await Container.create(app);

      expect(c.root.get<Db>(), same(c.injectorFor('database').get<Db>()));
      expect(c.root.get<UsesDb>(), isA<UsesDb>());
    });

    test('global module exports are visible without import', () async {
      final config = Module(
        id: 'config',
        global: true,
        providers: [Provider((i) => Config())],
        exports: [Config],
      );
      final deep = Module(id: 'deep', providers: [Provider((i) => Clock())]);
      final app = Module(id: 'app', imports: [config, deep]);

      final c = await Container.create(app);

      expect(c.injectorFor('deep').get<Config>(), same(c.root.get<Config>()));
    });

    test('factory receives the injector of its own module', () async {
      final database = Module(
        id: 'database',
        providers: [
          Provider((i) => Secret()),
          Provider((i) {
            expect(i.moduleId, 'database');
            i.get<Secret>(); // visible only inside database
            return Db();
          }),
        ],
        exports: [Db],
      );
      final app = Module(id: 'app', imports: [database]);

      final c = await Container.create(app);

      expect(c.root.get<Db>(), isA<Db>());
      expect(c.root.maybeGet<Secret>(), isNull);
    });

    test('async providers are awaited during startup', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider.async((i) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return Db();
          }),
          Provider((i) => UsesDb(i.get())), // declared after Db: allowed
          Provider((i) => Repo(i.get())),
          Provider((i) => Clock()),
        ],
      );

      final c = await Container.create(app);

      expect(c.root.get<Db>(), isA<Db>());
      expect(c.root.get<UsesDb>(), isA<UsesDb>());
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

    test(
      'plain async closure is awaited at startup and guarded in sync get',
      () async {
        final ok = await Container.create(
          Module(id: 'app', providers: [Provider((i) async => Db())]),
        );
        expect(ok.root.get<Db>(), isA<Db>());

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
      },
    );

    test('same key in two unrelated modules gives two instances', () async {
      final x = Module(id: 'x', providers: [Provider((i) => Clock())]);
      final y = Module(id: 'y', providers: [Provider((i) => Clock())]);
      final c = await Container.create(Module(id: 'app', imports: [x, y]));

      expect(
        c.injectorFor('x').get<Clock>(),
        isNot(same(c.injectorFor('y').get<Clock>())),
      );
      expect(c.root.maybeGet<Clock>(), isNull); // neither exports it
    });

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
  });
}
