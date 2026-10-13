import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class A {}

class B {}

({ModuleGraph graph, Module app, Module shared}) buildDiamond() {
  final shared = Module(id: 'shared');
  final users = Module(id: 'users', imports: [shared]);
  final orders = Module(id: 'orders', imports: [shared]);
  final app = Module(id: 'app', imports: [users, orders]);
  return (graph: ModuleGraph.build(app), app: app, shared: shared);
}

void main() {
  group('ModuleGraph.build', () {
    test('orders imports before importers with the root last', () {
      final ids = buildDiamond().graph.ordered.map((m) => m.id).toList();
      expect(ids, ['shared', 'users', 'orders', 'app']);
    });

    test('lists a shared module once', () {
      final ids = buildDiamond().graph.ordered.map((m) => m.id);
      expect(ids.where((id) => id == 'shared'), hasLength(1));
    });

    test('exposes the module it was built from as root', () {
      final diamond = buildDiamond();
      expect(diamond.graph.root, same(diamond.app));
    });

    test('byId returns the module instance', () {
      final diamond = buildDiamond();
      expect(diamond.graph.byId('shared'), same(diamond.shared));
    });

    test('contains is false for an unknown id', () {
      expect(buildDiamond().graph.contains('nope'), isFalse);
    });

    test('byId of an unknown id is an error', () {
      expect(
        () => buildDiamond().graph.byId('nope'),
        throwsA(isA<UnknownModuleError>()),
      );
    });

    test('a module importing itself is a cycle', () {
      final a = Module(id: 'a', imports: []);
      a.imports.add(a);
      expect(
        () => ModuleGraph.build(a),
        throwsA(
          isA<CircularModuleImportError>().having((e) => e.cycle, 'cycle', [
            'a',
            'a',
          ]),
        ),
      );
    });

    test(
      'a dynamic module imported twice with the same shape is one module',
      () {
        Module database({required String url}) => Module(
          id: 'database',
          providers: [Provider.value(url, token: const Token<String>('url'))],
          exports: [const Token<String>('url')],
        );
        final users = Module(
          id: 'users',
          imports: [database(url: 'x')],
        );
        final orders = Module(
          id: 'orders',
          imports: [database(url: 'x')],
        );
        final app = Module(id: 'app', imports: [users, orders]);

        final graph = ModuleGraph.build(app);

        expect(graph.ordered.where((m) => m.id == 'database'), hasLength(1));
      },
    );

    test('same id, different shape is an error', () {
      final one = Module(id: 'database', providers: [Provider((i) => A())]);
      final two = Module(id: 'database', providers: [Provider((i) => B())]);
      final app = Module(id: 'app', imports: [one, two]);

      expect(
        () => ModuleGraph.build(app),
        throwsA(
          isA<DuplicateModuleIdError>().having((e) => e.id, 'id', 'database'),
        ),
      );
    });

    test('import cycle is an error listing the cycle', () {
      // Growable list, so the test can close the cycle.
      final a = Module(id: 'a', imports: []);
      final b = Module(id: 'b', imports: [a]);
      a.imports.add(b);

      expect(
        () => ModuleGraph.build(Module(id: 'app', imports: [a])),
        throwsA(
          isA<CircularModuleImportError>().having((e) => e.cycle, 'cycle', [
            'a',
            'b',
            'a',
          ]),
        ),
      );
    });

    test('duplicate provider key in one module is an error', () {
      final m = Module(
        id: 'app',
        providers: [Provider((i) => A()), Provider((i) => A())],
      );
      expect(
        () => ModuleGraph.build(m),
        throwsA(isA<DuplicateProviderError>().having((e) => e.key, 'key', A)),
      );
    });

    test('exporting a key the module does not declare is an error', () {
      final m = Module(id: 'app', exports: [A]);
      expect(
        () => ModuleGraph.build(m),
        throwsA(isA<InvalidExportError>().having((e) => e.export, 'export', A)),
      );
    });

    test('re-exporting a module that is not imported is an error', () {
      final other = Module(id: 'other');
      final m = Module(id: 'app', exports: [other]);
      expect(() => ModuleGraph.build(m), throwsA(isA<InvalidExportError>()));
    });

    test('re-exporting an imported module is allowed', () {
      final db = Module(
        id: 'db',
        providers: [Provider((i) => A())],
        exports: [A],
      );
      final shared = Module(id: 'shared', imports: [db], exports: [db]);
      expect(ModuleGraph.build(shared).ordered.map((m) => m.id), [
        'db',
        'shared',
      ]);
    });

    test('modulesDeclaring finds every module with the key', () {
      final x = Module(id: 'x', providers: [Provider((i) => A())]);
      final y = Module(id: 'y', providers: [Provider((i) => A())]);
      final graph = ModuleGraph.build(Module(id: 'app', imports: [x, y]));
      expect(graph.modulesDeclaring(A), ['x', 'y']);
      expect(graph.modulesDeclaring(B), isEmpty);
    });
  });

  group('ModuleGraph.build start order', () {
    Module exporting(
      String id, {
      List<Module> imports = const [],
      bool global = false,
    }) => Module(
      id: id,
      imports: imports,
      global: global,
      providers: [Provider((i) => A())],
      exports: [A],
    );

    List<String> orderOf(Module root) =>
        ModuleGraph.build(root).ordered.map((m) => m.id).toList();

    test('global modules come before other modules', () {
      final users = Module(id: 'users');
      final config = exporting('config', global: true);
      final root = Module(id: 'root', imports: [users, config]);
      expect(orderOf(root), ['config', 'users', 'root']);
    });

    test('imports of a global module come before it', () {
      final env = Module(id: 'env');
      final users = Module(id: 'users');
      final config = exporting('config', imports: [env], global: true);
      final root = Module(id: 'root', imports: [users, config]);
      expect(orderOf(root), ['env', 'config', 'users', 'root']);
    });
  });

  group('ModuleGraph.build ambiguity', () {
    Module owner(String id) =>
        Module(id: id, providers: [Provider((i) => A())], exports: [A]);

    test('two imports exporting one key from different owners', () {
      final root = Module(id: 'root', imports: [owner('b'), owner('a')]);
      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<AmbiguousProviderError>()
              .having((e) => e.key, 'key', A)
              .having((e) => e.moduleId, 'moduleId', 'root')
              .having((e) => e.owners, 'owners', ['a', 'b']),
        ),
      );
    });

    test('one owner re-exported through several imports is fine', () {
      final a = owner('a');
      final left = Module(id: 'left', imports: [a], exports: [a]);
      final right = Module(id: 'right', imports: [a], exports: [a]);
      final root = Module(id: 'root', imports: [left, right]);
      expect(ModuleGraph.build(root).contains('root'), isTrue);
    });

    test('import beats a global with the same key', () {
      final global = Module(
        id: 'g',
        global: true,
        providers: [Provider((i) => A())],
        exports: [A],
      );
      final holder = Module(id: 'holder', imports: [global]);
      final root = Module(id: 'root', imports: [owner('a'), holder]);
      expect(ModuleGraph.build(root).contains('root'), isTrue);
    });

    test('two globals exporting one key from different owners', () {
      Module global(String id) => Module(
        id: id,
        global: true,
        providers: [Provider((i) => A())],
        exports: [A],
      );
      final root = Module(id: 'root', imports: [global('g1'), global('g2')]);
      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<AmbiguousProviderError>().having((e) => e.owners, 'owners', [
            'g1',
            'g2',
          ]),
        ),
      );
    });

    test('an own provider shadows ambiguous imports', () {
      final root = Module(
        id: 'root',
        imports: [owner('a'), owner('b')],
        providers: [Provider((i) => A())],
      );
      expect(ModuleGraph.build(root).contains('root'), isTrue);
    });
  });
}
