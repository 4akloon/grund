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
}
