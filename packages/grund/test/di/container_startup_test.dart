import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';

Future<Container> start(
  StubModule root, {
  List<Binding<Object>> overrides = const [],
}) => Container.create(ModuleGraph.build(root, overrides: overrides));

void main() {
  group('Container startup', () {
    test('creates singletons in dependency order, once', () async {
      final created = <String>[];
      final container = await start(
        AppModule(
          bindings: [
            Singleton<Service>((i) {
              created.add('Service');
              return Service(i());
            }, dependsOn: const [Key<Repo>()]),
            Singleton<Repo>((i) {
              created.add('Repo');
              return Repo(i());
            }, dependsOn: const [Key<Clock>()]),
            Singleton<Clock>((i) {
              created.add('Clock');
              return Clock();
            }, dependsOn: const []),
          ],
        ),
      );

      final service = container.root<Service>();

      expect(created, ['Clock', 'Repo', 'Service']);
      expect(service.repo.clock, same(container.root<Clock>()));
      expect(container.root<Service>(), same(service));
    });

    test(
      'resolves undeclared dependencies of a factory when it runs',
      () async {
        var clocks = 0;
        final container = await start(
          AppModule(
            bindings: [
              Singleton<Repo>.factory((i) => Repo(i())),
              Singleton<Clock>((i) {
                clocks++;
                return Clock();
              }, dependsOn: const []),
            ],
          ),
        );

        expect(container.root<Repo>().clock, same(container.root<Clock>()));
        expect(clocks, 1);
      },
    );

    test('waits for an asynchronous singleton declared in dependsOn', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
            Singleton<Db>((i) async {
              await Future<void>.delayed(Duration.zero);
              return Db();
            }, dependsOn: const []),
          ],
        ),
      );

      expect(container.root<UsesDb>(), isA<UsesDb>());
    });

    test(
      'rejects an asynchronous singleton that was not declared first',
      () async {
        final graph = ModuleGraph.build(
          AppModule(
            bindings: [
              Singleton<UsesDb>.factory((i) => UsesDb(i())),
              Singleton<Db>((i) async => Db(), dependsOn: const []),
            ],
          ),
        );

        await expectLater(
          Container.create(graph),
          throwsA(
            isA<AsyncProviderNotReadyError>().having(
              (e) => e.key,
              'key',
              const Key<Db>(),
            ),
          ),
        );
      },
    );

    test('detects a cycle that only the factories reveal', () async {
      final graph = ModuleGraph.build(
        AppModule(
          bindings: [
            Singleton<NeedsA>.factory((i) => NeedsA(i())),
            Singleton<NeedsB>.factory((i) => NeedsB(i())),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<CircularDependencyError>().having((e) => e.cycle, 'cycle', [
            const Key<NeedsA>(),
            const Key<NeedsB>(),
            const Key<NeedsA>(),
          ]),
        ),
      );
    });

    test('wraps a failing factory with the key, module and cause', () async {
      final graph = ModuleGraph.build(
        AppModule(
          bindings: [
            Singleton<Clock>(
              (i) => throw StateError('no clock'),
              dependsOn: const [],
            ),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<ProviderCreationError>()
              .having((e) => e.key, 'key', const Key<Clock>())
              .having((e) => e.module, 'module', 'AppModule')
              .having((e) => e.error, 'error', isA<StateError>())
              .having((e) => e.stackTrace, 'stackTrace', isNotNull),
        ),
      );
    });

    test('lets a grund error from a factory through unwrapped', () async {
      final graph = ModuleGraph.build(
        AppModule(bindings: [Singleton<Repo>.factory((i) => Repo(i()))]),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<MissingProviderError>().having(
            (e) => e.requiredBy,
            'requiredBy',
            const Key<Repo>(),
          ),
        ),
      );
    });

    test(
      'a module sees the exports of its imports, not their private bindings',
      () async {
        final container = await start(
          AppModule(
            imports: [
              DbModule(
                bindings: [
                  Singleton<Db>((i) => Db(), dependsOn: const []),
                  Singleton<Secret>((i) => Secret(), dependsOn: const []),
                ],
                exports: const [Key<Db>()],
              ),
            ],
          ),
        );

        expect(container.root<Db>(), isA<Db>());
        expect(container.root.maybe<Secret>(), isNull);
        expect(
          () => container.root<Secret>(),
          throwsA(isA<MissingProviderError>()),
        );
      },
    );

    test(
      'a factory sees what its own module sees, not what its caller sees',
      () async {
        final container = await start(
          AppModule(
            imports: [
              DbModule(
                bindings: [
                  Singleton<Secret>((i) => Secret(), dependsOn: const []),
                  Transient<UsesSecret>(
                    (i) => UsesSecret(i()),
                    dependsOn: const [Key<Secret>()],
                  ),
                ],
                exports: const [Key<UsesSecret>()],
              ),
            ],
          ),
        );

        expect(container.root<UsesSecret>(), isA<UsesSecret>());
      },
    );

    test('resolves a name', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<String>((i) => 'a', name: 'first', dependsOn: const []),
            Singleton<String>((i) => 'b', name: 'second', dependsOn: const []),
          ],
        ),
      );

      expect(container.root<String>('second'), 'b');
      expect(container.root.maybe<String>(), isNull);
    });

    test('a transient binding is a new instance each time', () async {
      final container = await start(
        AppModule(
          bindings: [Transient<Clock>((i) => Clock(), dependsOn: const [])],
        ),
      );

      expect(container.root<Clock>(), isNot(same(container.root<Clock>())));
    });

    test('all collects singletons whose binding type is a subtype', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<Repo>((i) => Repo(Clock()), dependsOn: const []),
            Singleton<Clock>((i) => Clock(), dependsOn: const []),
            Transient<Service>(
              (i) => Service(Repo(Clock())),
              dependsOn: const [],
            ),
          ],
        ),
      );

      expect(container.all<Object>(), hasLength(2));
      expect(container.all<Clock>(), hasLength(1));
      expect(container.all<Service>(), isEmpty);
    });

    test('overrides replace a binding for the whole start', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
            Singleton<Clock>((i) => Clock(), dependsOn: const []),
          ],
        ),
        overrides: [
          Singleton<Clock>((i) => _FixedClock(), dependsOn: const []),
        ],
      );

      expect(container.root<Repo>().clock, isA<_FixedClock>());
    });
  });
}

final class _FixedClock extends Clock {}
