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

Singleton<Db> db() => Singleton<Db>((i) => Db(), dependsOn: const []);

void main() {
  group('global module visibility', () {
    test('does not show a binding the global module does not export', () {
      final root = AppModule(
        imports: [
          ConfigModule(global: true, bindings: [clock()]),
          const AuthModule(),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility.lookup(
          const ModuleIdentity(AuthModule),
          const Key<Clock>(),
        ),
        isNull,
      );
    });

    test('rejects a key exported by two global modules', () {
      final root = AppModule(
        imports: [
          ConfigModule(
            global: true,
            bindings: [db()],
            exports: const [Key<Db>()],
          ),
          DbModule(global: true, bindings: [db()], exports: const [Key<Db>()]),
          const AuthModule(),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(isA<AmbiguousProviderError>()),
      );
    });

    test('lets an import shadow a global export', () {
      final root = AppModule(
        imports: [
          ConfigModule(
            global: true,
            bindings: [db()],
            exports: const [Key<Db>()],
          ),
          AuthModule(
            imports: [
              DbModule(bindings: [db()], exports: const [Key<Db>()]),
            ],
          ),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility
            .lookup(const ModuleIdentity(AuthModule), const Key<Db>())
            ?.owner,
        const ModuleIdentity(DbModule),
      );
    });
  });

  group('overrides across modules', () {
    test('replaces the key in every module that declares it', () {
      final replacement = db();
      final root = AppModule(
        bindings: [db()],
        imports: [
          DbModule(bindings: [db()]),
        ],
      );

      final graph = ModuleGraph.build(root, overrides: [replacement]);

      expect([
        for (final node in graph.nodes) node.bindings[const Key<Db>()],
      ], everyElement(same(replacement)));
    });
  });
}
