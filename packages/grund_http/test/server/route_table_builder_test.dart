import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/server/route_table_builder.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/probe_api.dart';

/// Starts a graph of [bindings] and builds its route table.
Future<List<String>> routesOf(
  List<Binding<Object>> bindings, {
  List<HookRef<HttpHook>> global = const [],
}) async {
  final app = await TestApp.start(root: ProbeModule(bindings));
  try {
    final table = await RouteTableBuilder.build(
      app.app.container.all<HttpApi>(),
      global,
    );
    return table.routes;
  } finally {
    await app.close();
  }
}

Route get(String path) => Route.get(path, (c) => null);

void main() {
  group('RouteTableBuilder', () {
    test('describes every route as METHOD /full/path, sorted', () async {
      final routes = await routesOf([
        ProbeApi.binding('users', [
          get('/:id'),
          Route.post('/', (c) => null),
        ], path: '/users'),
        ProbeApi.binding('root', [get('/health')]),
      ]);

      expect(routes, ['GET /health', 'GET /users/:id', 'POST /users']);
    });

    test('an API without routes contributes nothing', () async {
      expect(await routesOf([ProbeApi.binding('empty', [])]), isEmpty);
    });

    test('a duplicate in one API names both routes', () async {
      await expectLater(
        routesOf([
          ProbeApi.binding('a', [
            Route.get('/x', (c) => 1, name: 'first'),
            Route.get('/x', (c) => 2, name: 'second'),
          ]),
        ]),
        throwsA(
          isA<DuplicateRouteError>()
              .having((e) => e.method, 'method', 'GET')
              .having((e) => e.path, 'path', '/x')
              .having((e) => e.existing, 'existing', 'ProbeApi.first')
              .having((e) => e.duplicate, 'duplicate', 'ProbeApi.second'),
        ),
      );
    });

    test('a conflict between two APIs is found too (RF-4)', () async {
      await expectLater(
        routesOf([
          ProbeApi.binding('a', [get('/:id')], path: '/users'),
          ProbeApi.binding('b', [get('/:userId')], path: '/users'),
        ]),
        throwsA(isA<DuplicateRouteError>()),
      );
    });

    test('the same path with another method is not a conflict', () async {
      final routes = await routesOf([
        ProbeApi.binding('a', [get('/x')]),
        ProbeApi.binding('b', [Route.put('/x', (c) => null)]),
      ]);

      expect(routes, ['GET /x', 'PUT /x']);
    });

    test('an invalid pattern is reported with its text', () async {
      await expectLater(
        routesOf([
          ProbeApi.binding('a', [get('/a/*/b')]),
        ]),
        throwsA(isA<InvalidRoutePatternError>()),
      );
    });
  });

  group('RouteTableBuilder hooks (RF-4)', () {
    test('a global hook type nobody provides is a MissingProviderError', () {
      expect(
        routesOf(
          [
            ProbeApi.binding('a', [get('/')]),
          ],
          global: const [HookRef<UserHook>.type()],
        ),
        throwsA(isA<MissingProviderError>()),
      );
    });

    test('an API and a route hook are checked too', () {
      expect(
        routesOf([
          ProbeApi.binding(
            'a',
            [get('/')],
            use: const [HookRef<UserHook>.type()],
          ),
        ]),
        throwsA(isA<MissingProviderError>()),
      );
      expect(
        routesOf([
          ProbeApi.binding('a', [
            Route.get('/', (c) => null, use: const [HookRef<UserHook>.type()]),
          ]),
        ]),
        throwsA(isA<MissingProviderError>()),
      );
    });

    test('provided hook types and instances pass', () async {
      final routes = await routesOf([
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [get('/')],
          use: const [
            HookRef<UserHook>.type(),
            HookRef<UserHook>.instance(UserHook()),
          ],
        ),
      ]);

      expect(routes, ['GET /']);
    });
  });
}
