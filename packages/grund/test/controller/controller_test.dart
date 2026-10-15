import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Greeter {
  String greet(String name) => 'Hello, $name';
}

final class GreetController {
  GreetController(this.greeter);
  final Greeter greeter;

  String hello(String name) => greeter.greet(name);
}

final class Broken {
  Broken() {
    throw StateError('no config');
  }
}

final greetController = Controller<GreetController>(
  path: '/greet',
  create: (i) => GreetController(i.get()),
  metadata: const ['controller-level'],
  routes: [
    Route.get(
      '/:name',
      (c, ctx) async => c.hello(await ctx.param<String>('name')),
      name: 'hello',
    ),
    Route.post('/', (c, ctx) => 'posted'),
  ],
);

void main() {
  group('Route', () {
    test('factories set the method and default the name', () {
      final routes = <Route<GreetController>>[
        Route.get('/a', (c, ctx) => null),
        Route.post('/a', (c, ctx) => null),
        Route.put('/a', (c, ctx) => null),
        Route.patch('/a', (c, ctx) => null),
        Route.delete('/a', (c, ctx) => null, name: 'remove'),
      ];

      expect(routes.map((r) => r.method), [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
      ]);
      expect(routes.first.name, 'GET /a');
      expect(routes.last.name, 'remove');
      expect(routes.first.enhancers, same(Enhancers.none));
    });

    test('invoke calls the handler with the controller', () async {
      final controller = GreetController(Greeter());
      final context = contextFor(
        requestFor('GET', '/greet/ann'),
        pathParameters: {'name': 'ann'},
      );

      final result = await greetController.routes.first.invoke(
        controller,
        context,
      );

      expect(result, 'Hello, ann');
    });
  });

  group('Controller', () {
    test('instantiate uses the injector of the module', () async {
      final container = await Container.create(
        Module(id: 'app', providers: [Provider((i) => Greeter())]),
      );

      final instance = greetController.instantiate(container.root);

      expect(instance.greeter, same(container.root.get<Greeter>()));
      expect(greetController.type, GreetController);
      expect(greetController.path, '/greet');
      expect(greetController.metadata, ['controller-level']);
    });

    test('a throwing factory is wrapped with controller and module', () async {
      final container = await Container.create(Module(id: 'app'));
      final broken = Controller<Broken>(create: (i) => Broken(), routes: []);

      expect(
        () => broken.instantiate(container.root),
        throwsA(
          isA<ControllerCreationError>()
              .having((e) => e.controllerType, 'type', Broken)
              .having((e) => e.moduleId, 'module', 'app')
              .having((e) => e.error, 'error', isA<StateError>())
              .having((e) => e.message, 'message', contains('no config')),
        ),
      );
    });

    test('the wrapped error keeps the original stack trace', () async {
      final container = await Container.create(Module(id: 'app'));
      final broken = Controller<Broken>(create: (i) => Broken(), routes: []);

      StackTrace? thrownAt;
      try {
        broken.instantiate(container.root);
      } on ControllerCreationError catch (e, stackTrace) {
        thrownAt = stackTrace;
        expect(e.stackTrace.toString(), contains('Broken'));
      }

      expect(thrownAt.toString(), contains('Broken'));
    });

    test('DI errors from the factory pass through unchanged', () async {
      final container = await Container.create(Module(id: 'app'));

      expect(
        () => greetController.instantiate(container.root),
        throwsA(
          isA<MissingProviderError>().having((e) => e.key, 'key', Greeter),
        ),
      );
    });
  });

  group('Module.controllers', () {
    test('defaults to empty and keeps declaration order', () {
      final other = Controller<Greeter>(create: (i) => Greeter(), routes: []);
      final module = Module(id: 'm', controllers: [greetController, other]);

      expect(Module(id: 'x').controllers, isEmpty);
      expect(module.controllers.map((c) => c.type), [GreetController, Greeter]);
    });

    test('same length with different controller types is another shape', () {
      final first = Module(id: 'shared', controllers: [greetController]);
      final second = Module(
        id: 'shared',
        controllers: [
          Controller<Greeter>(create: (i) => Greeter(), routes: []),
        ],
      );

      expect(
        () => ModuleGraph.build(Module(id: 'app', imports: [first, second])),
        throwsA(isA<DuplicateModuleIdError>()),
      );
    });

    test('same controller types with other factories are the same shape', () {
      Module withFactory(Greeter Function() make) => Module(
        id: 'shared',
        controllers: [Controller<Greeter>(create: (i) => make(), routes: [])],
      );
      final first = withFactory(Greeter.new);
      final second = withFactory(() => Greeter());

      final graph = ModuleGraph.build(
        Module(id: 'app', imports: [first, second]),
      );

      expect(graph.ordered.where((m) => m.id == 'shared'), hasLength(1));
    });

    test('same id with different controllers is a duplicate module', () {
      final first = Module(id: 'shared', controllers: [greetController]);
      final second = Module(id: 'shared');

      expect(
        () => ModuleGraph.build(Module(id: 'app', imports: [first, second])),
        throwsA(isA<DuplicateModuleIdError>()),
      );
    });
  });
}
