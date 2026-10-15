import 'package:grund/grund.dart';
import 'package:grund/src/app/route_table_builder.dart';
import 'package:grund/src/routing/route_match.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';

final class PingController {
  String ping() => 'pong';
}

final class NeedsMissing implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

Controller<PingController> ping(
  String path, {
  Enhancers enhancers = Enhancers.none,
}) => Controller<PingController>(
  path: path,
  create: (i) => PingController(),
  enhancers: enhancers,
  routes: [Route.get('/', (c, ctx) => c.ping(), name: 'ping')],
);

void main() {
  group('RouteTableBuilder.validate', () {
    test('accepts the sample application', () {
      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(appModule())),
        returnsNormally,
      );
    });

    test('duplicate routes across modules name both handlers', () {
      final root = Module(
        id: 'app',
        imports: [
          Module(id: 'a', controllers: [ping('/ping')]),
          Module(id: 'b', controllers: [ping('ping/')]),
        ],
      );

      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(root)),
        throwsA(
          isA<DuplicateRouteError>()
              .having((e) => e.path, 'path', '/ping')
              .having(
                (e) => e.existing,
                'existing',
                'PingController.ping (module "a")',
              )
              .having(
                (e) => e.duplicate,
                'duplicate',
                'PingController.ping (module "b")',
              ),
        ),
      );
    });

    test('parameter names do not distinguish routes', () {
      final root = Module(
        id: 'app',
        controllers: [ping('/u/:id'), ping('/u/:name')],
      );

      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(root)),
        throwsA(isA<DuplicateRouteError>()),
      );
    });

    test('an invalid pattern is reported', () {
      final root = Module(id: 'app', controllers: [ping('/files/*/x')]);

      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(root)),
        throwsA(isA<InvalidRoutePatternError>()),
      );
    });
  });

  group('RouteTableBuilder.build', () {
    test('creates controllers and registers their routes', () async {
      final container = await Container.create(appModule());

      final router = RouteTableBuilder.build(container, Enhancers.none);

      final match = router.match('GET', ['users', '1']);
      expect(
        match,
        isA<RouteFound<Object>>().having((m) => m.parameters, 'parameters', {
          'id': '1',
        }),
      );
    });

    test('Use with no visible provider fails at startup', () async {
      final container = await Container.create(
        Module(
          id: 'app',
          controllers: [
            ping(
              '/',
              enhancers: const Enhancers(guards: [Use<NeedsMissing>()]),
            ),
          ],
        ),
      );

      expect(
        () => RouteTableBuilder.build(container, Enhancers.none),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', NeedsMissing)
              .having((e) => e.moduleId, 'module', 'app'),
        ),
      );
    });

    test('application Use resolves through the root module', () async {
      final container = await Container.create(
        Module(id: 'app', imports: [usersModule()]),
      );

      expect(
        () => RouteTableBuilder.build(
          container,
          const Enhancers(guards: [Use<AuthGuard>()]),
        ),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', AuthGuard)
              .having((e) => e.moduleId, 'module', 'app'),
        ),
      );
    });
  });
}
