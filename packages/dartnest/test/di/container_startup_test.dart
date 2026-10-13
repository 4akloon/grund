import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

void main() {
  group('Container.create startup', () {
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

    test('plain async closure is awaited at startup', () async {
      final c = await Container.create(
        Module(id: 'app', providers: [Provider((i) async => Db())]),
      );
      expect(c.root.get<Db>(), isA<Db>());
    });

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

    test('own provider shadows an import export with the same key', () async {
      final shared = Module(
        id: 'shared',
        providers: [Provider((i) => Clock())],
        exports: [Clock],
      );
      final app = Module(
        id: 'app',
        imports: [shared],
        providers: [Provider((i) => Clock())],
      );
      final c = await Container.create(app);
      expect(
        c.root.get<Clock>(),
        isNot(same(c.injectorFor('shared').get<Clock>())),
      );
    });

    test('two-level transitive re-export reaches the importer', () async {
      final c = Module(
        id: 'c',
        providers: [Provider((i) => Db())],
        exports: [Db],
      );
      final b = Module(id: 'b', imports: [c], exports: [c]);
      final a = Module(id: 'a', imports: [b], exports: [b]);
      final app = Module(
        id: 'app',
        imports: [a],
        providers: [Provider((i) => UsesDb(i.get()))],
      );
      final container = await Container.create(app);
      expect(
        container.root.get<Db>(),
        same(container.injectorFor('c').get<Db>()),
      );
    });

    test(
      'a global module\'s async export is ready for modules listed before it',
      () async {
        final users = Module(
          id: 'users',
          providers: [Provider((i) => UsesDb(i.get()))],
        );
        final config = Module(
          id: 'config',
          global: true,
          providers: [Provider.async((i) async => Db())],
          exports: [Db],
        );
        final app = Module(id: 'app', imports: [users, config]);

        final c = await Container.create(app);

        expect(c.injectorFor('users').get<UsesDb>(), isA<UsesDb>());
      },
    );
  });
}
