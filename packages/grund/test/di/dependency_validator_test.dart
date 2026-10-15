import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/creation_plan.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/di/module_identity.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';

Singleton<Clock> clock() =>
    Singleton<Clock>((i) => Clock(), dependsOn: const []);

Singleton<Repo> repo() =>
    Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]);

void main() {
  group('dependency validation', () {
    test('accepts dependencies in any declaration order', () {
      final root = AppModule(bindings: [repo(), clock()]);

      expect(() => ModuleGraph.build(root), returnsNormally);
    });

    test('rejects a dependency nothing provides', () {
      final root = AppModule(bindings: [repo()]);

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', const Key<Clock>())
              .having((e) => e.requiredBy, 'requiredBy', const Key<Repo>())
              .having((e) => e.module, 'module', 'AppModule'),
        ),
      );
    });

    test('names the module that declares a key which is not exported', () {
      final root = AppModule(
        bindings: [repo()],
        imports: [
          DbModule(bindings: [clock()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ProviderNotVisibleError>()
              .having((e) => e.declaredIn, 'declaredIn', ['DbModule'])
              .having((e) => e.importChain, 'importChain', [
                'AppModule',
                'DbModule',
              ]),
        ),
      );
    });

    test('shows the import chain when the declaring module is indirect', () {
      final root = AppModule(
        bindings: [repo()],
        imports: [
          AuthModule(
            imports: [
              DbModule(bindings: [clock()]),
            ],
          ),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ProviderNotVisibleError>().having(
            (e) => e.importChain,
            'importChain',
            ['AppModule', 'AuthModule', 'DbModule'],
          ),
        ),
      );
    });

    test('has no chain when the declaring module cannot be reached', () {
      final root = AppModule(
        imports: [
          DbModule(bindings: [repo()]),
          AuthModule(bindings: [clock()], exports: const [Key<Clock>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ProviderNotVisibleError>()
              .having((e) => e.module, 'module', 'DbModule')
              .having((e) => e.declaredIn, 'declaredIn', ['AuthModule'])
              .having((e) => e.importChain, 'importChain', isEmpty),
        ),
      );
    });

    test('rejects a dependency cycle and prints it', () {
      final root = AppModule(
        bindings: [
          Singleton<NeedsA>(
            (i) => NeedsA(i()),
            dependsOn: const [Key<NeedsB>()],
          ),
          Singleton<NeedsB>(
            (i) => NeedsB(i()),
            dependsOn: const [Key<NeedsA>()],
          ),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<CircularDependencyError>().having((e) => e.cycle, 'cycle', [
            const Key<NeedsA>(),
            const Key<NeedsB>(),
            const Key<NeedsA>(),
          ]),
        ),
      );
    });

    test('rejects a binding that depends on itself', () {
      final root = AppModule(
        bindings: [
          Transient<Clock>((i) => Clock(), dependsOn: const [Key<Clock>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(isA<CircularDependencyError>()),
      );
    });

    test('rejects a singleton that depends on a scoped binding', () {
      final root = AppModule(
        bindings: [
          Scoped<Db>((i) => Db(), dependsOn: const []),
          Singleton<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<CaptiveDependencyError>()
              .having((e) => e.singleton, 'singleton', const Key<UsesDb>())
              .having((e) => e.scoped, 'scoped', const Key<Db>()),
        ),
      );
    });

    test(
      'rejects a singleton that reaches a scoped binding through a transient',
      () {
        final root = AppModule(
          bindings: [
            Scoped<Db>((i) => Db(), dependsOn: const []),
            Transient<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
            Singleton<Repo>(
              (i) => Repo(Clock()),
              dependsOn: const [Key<UsesDb>()],
            ),
          ],
        );

        expect(
          () => ModuleGraph.build(root),
          throwsA(
            isA<CaptiveDependencyError>().having((e) => e.path, 'path', [
              const Key<Repo>(),
              const Key<UsesDb>(),
              const Key<Db>(),
            ]),
          ),
        );
      },
    );

    test('lets scoped and transient bindings depend on scoped ones', () {
      final root = AppModule(
        bindings: [
          Scoped<Db>((i) => Db(), dependsOn: const []),
          Scoped<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
          Transient<Repo>(
            (i) => Repo(Clock()),
            dependsOn: const [Key<UsesDb>()],
          ),
        ],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });

    test('skips bindings whose dependencies are not declared', () {
      final root = AppModule(
        bindings: [Singleton<Repo>.factory((i) => Repo(i()))],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });
  });

  group('CreationPlan', () {
    test('creates dependencies first, across modules', () {
      final root = AppModule(
        bindings: [repo()],
        imports: [
          DbModule(bindings: [clock()], exports: const [Key<Clock>()]),
        ],
      );

      final order = CreationPlan.of(ModuleGraph.build(root)).order;

      expect(order, [
        (const ModuleIdentity(DbModule), const Key<Clock>()),
        (const ModuleIdentity(AppModule), const Key<Repo>()),
      ]);
    });

    test('follows declared dependencies through transient bindings', () {
      final root = AppModule(
        bindings: [
          Singleton<Repo>(
            (i) => Repo(Clock()),
            dependsOn: const [Key<UsesDb>()],
          ),
          Transient<UsesDb>(
            (i) => UsesDb(i()),
            dependsOn: const [Key<Clock>()],
          ),
          clock(),
        ],
      );

      final keys = [
        for (final (_, key) in CreationPlan.of(ModuleGraph.build(root)).order)
          key,
      ];

      expect(keys, [const Key<Clock>(), const Key<Repo>()]);
    });

    test('lists singletons only', () {
      final root = AppModule(
        bindings: [
          clock(),
          Scoped<Db>((i) => Db(), dependsOn: const []),
          Transient<Config>((i) => Config(), dependsOn: const []),
        ],
      );

      expect(CreationPlan.of(ModuleGraph.build(root)).order, hasLength(1));
    });
  });
}
