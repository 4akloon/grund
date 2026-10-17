import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/di/module_identity.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';

Singleton<Clock> clock() =>
    Singleton<Clock>((i) => Clock(), dependsOn: const []);

Singleton<Db> db({String? name}) =>
    Singleton<Db>((i) => Db(), name: name, dependsOn: const []);

List<String> names(ModuleGraph graph) => [
  for (final node in graph.nodes) '${node.identity}',
];

void main() {
  group('ModuleGraph structure', () {
    test('orders imports before importers, the root last', () {
      const root = AppModule(
        imports: [
          AuthModule(imports: [DbModule()]),
          DbModule(),
        ],
      );

      expect(names(ModuleGraph.build(root)), [
        'DbModule',
        'AuthModule',
        'AppModule',
      ]);
    });

    test('puts global modules and their imports first', () {
      const root = AppModule(
        imports: [
          AuthModule(),
          ConfigModule(global: true, imports: [DbModule()]),
        ],
      );

      expect(names(ModuleGraph.build(root)), [
        'DbModule',
        'ConfigModule',
        'AuthModule',
        'AppModule',
      ]);
    });

    test('a module imported from two places is one node', () {
      const root = AppModule(
        imports: [
          AuthModule(imports: [DbModule()]),
          DbModule(),
        ],
      );

      expect(
        names(ModuleGraph.build(root)).where((n) => n == 'DbModule'),
        hasLength(1),
      );
    });

    test('qualifiers make two instances of one class two modules', () {
      const root = AppModule(
        imports: [
          DbModule(qualifier: 'a'),
          DbModule(qualifier: 'b'),
        ],
      );

      expect(names(ModuleGraph.build(root)), [
        "DbModule('a')",
        "DbModule('b')",
        'AppModule',
      ]);
      expect(
        ModuleGraph.build(root).nodeOf(const ModuleIdentity(DbModule, 'a')),
        isNotNull,
      );
    });

    test('rejects one identity imported with two shapes', () {
      final root = AppModule(
        imports: [
          const DbModule(),
          AuthModule(
            imports: [
              DbModule(bindings: [db()]),
            ],
          ),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ConflictingModuleError>().having(
            (e) => e.module,
            'module',
            'DbModule',
          ),
        ),
      );
    });

    test(
      'accepts one identity imported with the same shape and other factories',
      () {
        final root = AppModule(
          imports: [
            DbModule(bindings: [db()]),
            AuthModule(
              imports: [
                DbModule(bindings: [db()]),
              ],
            ),
          ],
        );

        expect(() => ModuleGraph.build(root), returnsNormally);
      },
    );

    test('rejects an import cycle with the path', () {
      // The cycle cannot be written with const values, so build it lazily.
      final a = _Cyclic('a');
      final b = _Cyclic('b');
      a.next = b;
      b.next = a;

      expect(
        () => ModuleGraph.build(a),
        throwsA(
          isA<CircularModuleImportError>().having(
            (e) => e.cycle,
            'cycle',
            hasLength(3),
          ),
        ),
      );
    });

    test('rejects a key declared twice in one module', () {
      final root = AppModule(bindings: [db(), db()]);

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<DuplicateBindingError>().having(
            (e) => e.key,
            'key',
            const Key<Db>(),
          ),
        ),
      );
    });

    test('allows the same type under different names', () {
      final root = AppModule(
        bindings: [
          db(name: 'a'),
          db(name: 'b'),
        ],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });

    test('rejects an export that is not declared', () {
      const root = AppModule(exports: [Key<Db>()]);

      expect(() => ModuleGraph.build(root), throwsA(isA<InvalidExportError>()));
    });

    test('rejects an exported module that is not imported', () {
      const root = AppModule(exports: [DbModule()]);

      expect(() => ModuleGraph.build(root), throwsA(isA<InvalidExportError>()));
    });

    test('rejects an export that is neither a key nor a module', () {
      const root = AppModule(exports: ['Db']);

      expect(() => ModuleGraph.build(root), throwsA(isA<InvalidExportError>()));
    });
  });

  group('ModuleGraph visibility', () {
    test('a module sees its own bindings and the exports of its imports', () {
      final root = AppModule(
        bindings: [clock()],
        imports: [
          DbModule(bindings: [db()], exports: const [Key<Db>()]),
        ],
      );

      final graph = ModuleGraph.build(root);
      const app = ModuleIdentity(AppModule);

      expect(graph.visibility.lookup(app, const Key<Clock>()), isNotNull);
      expect(
        graph.visibility.lookup(app, const Key<Db>())?.owner,
        const ModuleIdentity(DbModule),
      );
    });

    test('what a module does not export stays private', () {
      final root = AppModule(
        imports: [
          DbModule(bindings: [db()]),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility
            .lookup(const ModuleIdentity(AppModule), const Key<Db>()),
        isNull,
      );
    });

    test('a re-exported module passes its exports through', () {
      final root = AppModule(
        imports: [
          AuthModule(
            imports: [
              DbModule(bindings: [db()], exports: const [Key<Db>()]),
            ],
            exports: const [DbModule()],
          ),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility
            .lookup(const ModuleIdentity(AppModule), const Key<Db>()),
        isNotNull,
      );
    });

    test('a global module is visible without being imported', () {
      final root = AppModule(
        imports: [
          ConfigModule(
            global: true,
            bindings: [clock()],
            exports: const [Key<Clock>()],
          ),
          const AuthModule(),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility
            .lookup(const ModuleIdentity(AuthModule), const Key<Clock>()),
        isNotNull,
      );
    });

    test('an own binding shadows an import', () {
      final root = AppModule(
        bindings: [db()],
        imports: [
          DbModule(bindings: [db()], exports: const [Key<Db>()]),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility
            .lookup(const ModuleIdentity(AppModule), const Key<Db>())
            ?.owner,
        const ModuleIdentity(AppModule),
      );
    });

    test('rejects a key exported by two imports', () {
      final root = AppModule(
        imports: [
          DbModule(bindings: [db()], exports: const [Key<Db>()]),
          AuthModule(bindings: [db()], exports: const [Key<Db>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<AmbiguousProviderError>().having((e) => e.owners, 'owners', [
            'AuthModule',
            'DbModule',
          ]),
        ),
      );
    });

    test('one provider reachable by two paths is not ambiguous', () {
      final shared = DbModule(bindings: [db()], exports: const [Key<Db>()]);
      final root = AppModule(
        imports: [
          shared,
          AuthModule(imports: [shared], exports: [shared]),
        ],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });
  });

  group('ModuleGraph overrides', () {
    test('replaces the binding of the key', () {
      final replacement = Singleton<Clock>((i) => Clock(), dependsOn: const []);
      final root = AppModule(bindings: [clock()]);

      final graph = ModuleGraph.build(root, overrides: [replacement]);

      expect(graph.root.bindings, hasLength(1));
      expect(graph.root.bindings[const Key<Clock>()], same(replacement));
    });

    test('rejects an override that matches nothing', () {
      final root = AppModule(bindings: [clock()]);

      expect(
        () => ModuleGraph.build(root, overrides: [db()]),
        throwsA(
          isA<UnusedOverrideError>().having(
            (e) => e.key,
            'key',
            const Key<Db>(),
          ),
        ),
      );
    });
  });
}

final class _Cyclic extends StubModule {
  _Cyclic(this.label);

  final String label;

  /// Set right after construction, before the graph is built, to close a cycle.
  late StubModule next;

  @override
  Object? get qualifier => label;

  @override
  List<StubModule> get imports => [next];
}
