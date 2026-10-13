import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/app/request_dispatcher.dart';
import 'package:dartnest/src/app/route_table_builder.dart';
import 'package:dartnest/src/pipeline/endpoint.dart';
import 'package:dartnest/src/pipeline/http_error_responder.dart';
import 'package:dartnest/src/pipeline/response_serializer.dart';
import 'package:dartnest/src/routing/router.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class FilesController {
  String read(String path) => 'file $path';
}

final filesController = Controller<FilesController>(
  path: '/files',
  create: (i) => FilesController(),
  routes: [
    Route.get('/:name', (c, ctx) async => c.read(await ctx.param('name'))),
    Route.get('/raw/*', (c, ctx) async => c.read(await ctx.param('*'))),
  ],
);

final class HeaderThenFailGuard implements Guard {
  const HeaderThenFailGuard();

  @override
  bool canActivate(ExecutionContext context) {
    context.switchToHttp().response.headers.set('x-trace', 'abc');
    throw StateError('boom');
  }
}

final class RecordingFilter extends ExceptionFilter<Object> {
  RecordingFilter(this.seen);
  final List<Object> seen;

  @override
  Object? handle(Object error, ExecutionContext context) {
    seen.add(error);
    return 'handled';
  }
}

final boomController = Controller<FilesController>(
  path: '/boom',
  create: (i) => FilesController(),
  routes: [
    Route.get(
      '/',
      (c, ctx) => c.read('x'),
      enhancers: const Enhancers(guards: [HeaderThenFailGuard()]),
    ),
  ],
);

Future<(RequestDispatcher, Router<Endpoint>)> dispatcherFor(
  Module root, [
  Enhancers enhancers = Enhancers.none,
]) async {
  final container = await Container.create(root);
  final dispatcher = RequestDispatcher(
    serializer: ResponseSerializer(SerializerRegistry()),
    errors: HttpErrorResponder(debug: false, log: (_, _) {}),
  );
  return (dispatcher, RouteTableBuilder.build(container, enhancers));
}

Future<Object?> jsonOf(HttpResponse response) async =>
    jsonDecode(utf8.decode(await response.body.readAll()));

void main() {
  late RequestDispatcher dispatcher; // set in setUp before every test
  late Router<Endpoint> router; // set in setUp before every test

  Future<HttpResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    String? body,
  }) => dispatcher.dispatch(
    requestFor(method, target, headers: headers, body: body),
    router,
  );

  setUp(() async {
    (dispatcher, router) = await dispatcherFor(
      Module(
        id: 'app',
        imports: [usersModule()],
        controllers: [filesController, boomController],
      ),
    );
  });

  group('RequestDispatcher', () {
    test('runs the handler and serializes the result', () async {
      final response = await send('GET', '/users/1');

      expect(response.status, 200);
      expect(await jsonOf(response), {'id': 1, 'name': 'ann'});
    });

    test('unknown path is 404 with the default body', () async {
      final response = await send('GET', '/nope');

      expect(response.status, 404);
      expect(await jsonOf(response), {
        'statusCode': 404,
        'error': 'Not Found',
        'message': 'Cannot GET /nope',
      });
    });

    test('wrong method is 405 with allow', () async {
      final response = await send('DELETE', '/users/1');

      expect(response.status, 405);
      expect(response.headers['allow'], 'GET, HEAD');
    });

    test('controller filter maps a domain error', () async {
      final response = await send('GET', '/users/99');

      expect(response.status, 404);
      expect((await jsonOf(response) as Map)['message'], 'No user 99');
    });

    test('guard header survives the error response', () async {
      final response = await send('POST', '/users', body: '{"name":"cy"}');

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
    });

    test('head status and location from the handler', () async {
      final response = await send(
        'POST',
        '/users',
        headers: {'authorization': 'Bearer admin'},
        body: '{"name":"cy"}',
      );

      expect(response.status, 201);
      expect(response.headers['location'], '/users/3');
      expect(await jsonOf(response), {'id': 3, 'name': 'cy'});
    });

    test('route metadata reaches the guard: non-admin is 403', () async {
      final response = await send(
        'POST',
        '/users',
        headers: {'authorization': 'Bearer user'},
        body: '{"name":"cy"}',
      );

      expect(response.status, 403);
    });

    // Review Focus 4: path normalization and decoding.
    test('trailing and repeated slashes, percent-decoding, wildcard', () async {
      expect((await send('GET', '/users/')).status, 200);
      expect(await jsonOf(await send('GET', '/users//2')), {
        'id': 2,
        'name': 'bob',
      });
      expect(
        utf8.decode(await (await send('GET', '/files/a%20b')).body.readAll()),
        'file a b',
      );
      expect(
        utf8.decode(
          await (await send('GET', '/files/raw/x/y%2Fz')).body.readAll(),
        ),
        'file x/y/z',
      );
    });

    test('invalid percent-encoded UTF-8 is 400', () async {
      for (final target in ['/files/%FF', '/files/%C3']) {
        final response = await send('GET', target);

        expect(response.status, 400, reason: target);
        expect(
          (await jsonOf(response) as Map)['message'],
          'Malformed percent-encoding in path',
        );
      }
    });

    test('an invalid escape sequence stays a literal segment', () async {
      final response = await send('GET', '/files/%zz');

      expect(response.status, 200);
      expect(utf8.decode(await response.body.readAll()), 'file %zz');
    });

    test('a non-HttpException keeps head headers on the 500', () async {
      final response = await send('GET', '/boom');

      expect(response.status, 500);
      expect(response.headers['x-trace'], 'abc');
    });

    test('404 and 405 bypass user exception filters', () async {
      final seen = <Object>[];
      final (d, r) = await dispatcherFor(
        Module(id: 'app', imports: [usersModule()]),
        Enhancers(filters: [RecordingFilter(seen)]),
      );

      final notFound = await d.dispatch(requestFor('GET', '/nope'), r);
      final wrongMethod = await d.dispatch(requestFor('DELETE', '/users/1'), r);

      expect(notFound.status, 404);
      expect(wrongMethod.status, 405);
      expect(seen, isEmpty);
    });

    test('HEAD is routed to GET', () async {
      expect((await send('HEAD', '/users/1')).status, 200);
    });
  });
}
