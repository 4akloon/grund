import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

/// The module `app` with [providers] and the imports [imports].
Module appWith(
  List<ProviderSpec> providers, {
  List<Module> imports = const [],
}) => Module(id: 'app', imports: imports, providers: providers);

void main() {
  group('Container.reassemble', () {
    test(
      'keeps the instance of a provider whose module and key stay',
      () async {
        var clocks = 0;
        ProviderSpec clock() => Provider((i) {
          clocks++;
          return Clock();
        });
        final first = await Container.create(appWith([clock()]));

        final second = await first.reassemble(appWith([clock()]));

        expect(second.root.get<Clock>(), same(first.root.get<Clock>()));
        expect(clocks, 1);
      },
    );

    test('creates new providers with the kept ones as dependencies', () async {
      final first = await Container.create(appWith([Provider((i) => Clock())]));

      final second = await first.reassemble(
        appWith([Provider((i) => Clock()), Provider((i) => Repo(i.get()))]),
      );

      expect(second.root.get<Repo>().clock, same(first.root.get<Clock>()));
    });

    test('drops providers that are gone', () async {
      final first = await Container.create(
        appWith([Provider((i) => Clock()), Provider((i) => Db())]),
      );

      final second = await first.reassemble(
        appWith([Provider((i) => Clock())]),
      );

      expect(second.root.maybeGet<Db>(), isNull);
      expect(first.root.get<Db>(), isA<Db>());
    });

    test('a provider that moved to another module is created anew', () async {
      final first = await Container.create(appWith([Provider((i) => Clock())]));
      final time = Module(
        id: 'time',
        providers: [Provider((i) => Clock())],
        exports: [Clock],
      );

      final second = await first.reassemble(appWith(const [], imports: [time]));

      expect(second.root.get<Clock>(), isNot(same(first.root.get<Clock>())));
    });

    test(
      'keeps an async provider without awaiting its factory again',
      () async {
        var connections = 0;
        ProviderSpec db() => Provider.async((i) async {
          connections++;
          return Db();
        });
        final first = await Container.create(appWith([db()]));

        final second = await first.reassemble(appWith([db()]));

        expect(second.root.get<Db>(), same(first.root.get<Db>()));
        expect(connections, 1);
      },
    );

    test('a graph error leaves the previous container working', () async {
      final first = await Container.create(appWith([Provider((i) => Clock())]));
      final broken = appWith([
        Provider((i) => Clock()),
        Provider((i) => Clock()),
      ]);

      await expectLater(
        first.reassemble(broken),
        throwsA(isA<DuplicateProviderError>()),
      );
      expect(first.root.get<Clock>(), isA<Clock>());
    });

    test(
      'a failing new factory leaves the previous container working',
      () async {
        final first = await Container.create(
          appWith([Provider((i) => Clock())]),
        );
        final failing = appWith([
          Provider((i) => Clock()),
          Provider<Db>((i) => throw StateError('no database')),
        ]);

        await expectLater(
          first.reassemble(failing),
          throwsA(isA<ProviderCreationError>()),
        );
        expect(first.root.get<Clock>(), isA<Clock>());
        expect(first.root.maybeGet<Db>(), isNull);
      },
    );
  });
}
