import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/dispatch_harness.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/probe_api.dart';

class Item {
  Map<String, Object?> toJson() => {'id': 1};
}

void main() {
  late DispatchHarness harness;

  setUp(() async {
    harness = await DispatchHarness.start([
      ProbeApi.binding('items', [
        Route.get('/', (c) => [Item()]),
        Route.get('/:id', (c) => {'id': c.path.string('id')}),
        Route.post('/', (c) => Item(), status: 201),
        Route.get('/files/*', (c) => c.path.string('*')),
        Route.get('/none', (c) => null),
        Route.get('/broken', (c) => throw StateError('db password is hunter2')),
        Route.get('/missing', (c) => throw const NotFoundException()),
      ], path: '/items'),
    ]);
  });
  tearDown(() => harness.close());

  group('RequestDispatcher routing', () {
    test('answers a matched route with its result as JSON', () async {
      final response = await harness.send('GET', '/items/7');

      expect(response.status, 200);
      expect(await jsonOf(response), {'id': '7'});
    });

    test('an unknown path is a 404 problem+json (RF-3)', () async {
      final response = await harness.send('GET', '/nothing/here');

      expect(response.status, 404);
      expect(response.headers['content-type'], 'application/problem+json');
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Not Found',
        'status': 404,
        'detail': 'Cannot GET /nothing/here',
        'instance': '/nothing/here',
        'code': 'route_not_found',
      });
    });

    test('another method on a known path is a 405 with Allow (RF-3)', () async {
      final response = await harness.send('DELETE', '/items');

      expect(response.status, 405);
      expect(response.headers['allow'], 'GET, HEAD, POST');
      expect((await jsonOf(response) as Map)['code'], 'method_not_allowed');
    });

    test('HEAD is answered by the GET route', () async {
      final response = await harness.send('HEAD', '/items/7');

      expect(response.status, 200);
    });

    test('extra and trailing slashes do not change the match (RF-3)', () async {
      for (final target in ['/items/', '/items//', '/items///']) {
        final response = await harness.send('GET', target);
        expect(response.status, 200, reason: target);
      }
      expect(await jsonOf(await harness.send('GET', '/items//7/')), {
        'id': '7',
      });
    });

    test('percent-encoding is decoded per segment (RF-3)', () async {
      final spaced = await harness.send('GET', '/items/a%20b');
      final slash = await harness.send('GET', '/items/a%2Fb');

      expect(await jsonOf(spaced), {'id': 'a b'});
      expect(await jsonOf(slash), {'id': 'a/b'});
    });

    test('invalid percent-encoding is a 400, not a 500 (RF-3)', () async {
      final response = await harness.send('GET', '/items/%E0%A4%A');

      expect(response.status, 400);
      expect(response.headers['content-type'], 'application/problem+json');
      expect(harness.log.unhandledErrors, isEmpty);
    });

    test('a wildcard captures the rest of the path', () async {
      final response = await harness.send('GET', '/items/files/a/b/c.txt');

      expect(await textOf(response), 'a/b/c.txt');
    });
  });

  group('RequestDispatcher responses', () {
    test('null is 204 and the route status wins over the default', () async {
      final none = await harness.send('GET', '/items/none');
      final created = await harness.send('POST', '/items');

      expect(none.status, 204);
      expect(created.status, 201);
      expect(await jsonOf(created), {'id': 1});
    });

    test('an HttpException of the handler keeps its status', () async {
      final response = await harness.send('GET', '/items/missing');

      expect(response.status, 404);
      expect(harness.log.unhandledErrors, isEmpty);
    });

    test('an unexpected error is a logged 500 without internals', () async {
      final response = await harness.send('GET', '/items/broken');

      expect(response.status, 500);
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Internal Server Error',
        'status': 500,
        'detail': 'Internal server error',
        'instance': '/items/broken',
      });
      expect(harness.log.unhandledErrors, hasLength(1));
      expect(harness.log.unhandledErrors.single, isA<StateError>());
    });

    test('a bad query value is a 400 with a pointer (RF-3)', () async {
      final api = await DispatchHarness.start([
        ProbeApi.binding('p', [
          Route.get('/', (c) => c.query.integer('page', min: 1)),
        ]),
      ]);
      addTearDown(api.close);

      final response = await api.send('GET', '/?page=abc');

      expect(response.status, 400);
      expect(((await jsonOf(response) as Map)['errors'] as List).single, {
        'detail':
            'Invalid query parameter "page": expected an integer, '
            'got "abc".',
        'pointer': '/query/page',
        'code': 'parameter_invalid',
      });
    });
  });
}
