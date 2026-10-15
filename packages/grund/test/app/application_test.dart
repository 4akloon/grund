import 'dart:async';
import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class Answer {
  Answer(this.text);
  final String text;
}

/// A module whose `GET /slow` waits for [gate] and answers [label].
Module slowModule(String label, Completer<void> gate) => Module(
  id: 'slow',
  controllers: [
    Controller<Answer>(
      create: (i) => Answer(label),
      routes: [
        Route.get('/slow', (c, ctx) async {
          await gate.future;
          return c.text;
        }),
      ],
    ),
  ],
);

Future<String> textOf(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void silent(Object error, StackTrace stackTrace) {}

void main() {
  group('Application.create', () {
    test('takes a module function and answers through handle', () async {
      final app = await Application.create(appModule, onError: silent);

      final response = await app.handle(requestFor('GET', '/users/2'));

      expect(response.status, 200);
      expect(await textOf(response), '{"id":2,"name":"bob"}');
      expect(app.container.injectorFor('users').get<UsersService>(), isNotNull);
    });

    test('fromModule takes a module value', () async {
      final app = await Application.fromModule(appModule(), onError: silent);

      expect((await app.handle(requestFor('GET', '/users'))).status, 200);
    });

    test('a bad route fails before any provider is created', () async {
      var created = false;
      final root = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created = true;
            return Answer('x');
          }),
        ],
        controllers: [
          Controller<Answer>(
            create: (i) => i.get(),
            routes: [Route.get('/*/x', (c, ctx) => c.text)],
          ),
        ],
      );

      await expectLater(
        Application.fromModule(root),
        throwsA(isA<InvalidRoutePatternError>()),
      );
      expect(created, isFalse);
    });

    test('a duplicate route fails before any provider is created', () async {
      var created = false;
      final root = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created = true;
            return Answer('x');
          }),
        ],
        controllers: [
          Controller<Answer>(
            create: (i) => Answer('x'),
            routes: [
              Route.get('/same', (c, ctx) => c.text),
              Route.get('/same', (c, ctx) => c.text),
            ],
          ),
        ],
      );

      await expectLater(
        Application.fromModule(root),
        throwsA(isA<RoutingError>()),
      );
      expect(created, isFalse);
    });

    test('application enhancers resolve through the root module', () async {
      final app = await Application.create(
        () => Module(
          id: 'app',
          imports: [usersModule()],
          providers: [Provider((i) => AuthGuard())],
        ),
        enhancers: const Enhancers(guards: [Use<AuthGuard>()]),
        onError: silent,
      );

      expect((await app.handle(requestFor('GET', '/users'))).status, 401);
    });

    test('serializers registered on the app are used', () async {
      final app = await Application.create(
        () => Module(
          id: 'app',
          controllers: [
            Controller<Answer>(
              create: (i) => Answer('x'),
              routes: [Route.get('/', (c, ctx) => c)],
            ),
          ],
        ),
        onError: silent,
      );
      app.serializers.register<Answer>((a) => {'text': a.text});

      expect(
        await textOf(await app.handle(requestFor('GET', '/'))),
        '{"text":"x"}',
      );
    });
  });

  group('Application middleware', () {
    test('runs in registration order around routing', () async {
      final app = await Application.create(appModule, onError: silent);
      final log = <String>[];
      app
        ..use((request, next) async {
          log.add('outer in');
          final response = await next();
          log.add('outer out');
          return response.mergeHeaders(HeaderMap.of({'x-outer': '1'}));
        })
        ..use((request, next) async {
          log.add('inner');
          return next();
        });

      final response = await app.handle(requestFor('GET', '/nope'));

      expect(response.status, 404);
      expect(response.headers['x-outer'], '1');
      expect(log, ['outer in', 'inner', 'outer out']);
    });

    test('can answer without routing, errors become 500', () async {
      final errors = <Object>[];
      final app = await Application.create(
        appModule,
        onError: (error, _) => errors.add(error),
      );
      app.use((request, next) async {
        if (request.uri.path == '/boom') throw StateError('boom');
        return HttpResponse.text('short');
      });

      expect(
        await textOf(await app.handle(requestFor('GET', '/users'))),
        'short',
      );
      expect((await app.handle(requestFor('GET', '/boom'))).status, 500);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('Application middleware snapshot', () {
    test('middleware added while a request runs does not join it', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => slowModule('old', gate));
      final log = <String>[];
      app.use((request, next) async {
        await gate.future;
        return next();
      });

      final inFlight = app.handle(requestFor('GET', '/slow'));
      app.use((request, next) {
        log.add('late');
        return next();
      });
      gate.complete();
      await inFlight;
      await app.handle(requestFor('GET', '/slow'));

      expect(log, ['late']);
    });
  });
}
