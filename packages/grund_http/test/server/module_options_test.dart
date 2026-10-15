import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/fake_adapter.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';

final class _Money {
  const _Money(this.cents);

  final int cents;
}

final class _Header implements Middleware {
  _Header(this.name, this.events);

  final String name;
  final List<String> events;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    events.add('in $name');
    final response = await next();
    events.add('out $name');
    return response.mergeHeaders(HeaderMap.of({'x-$name': 'yes'}));
  }
}

final class _Failing implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) =>
      throw StateError('middleware broke');
}

final class _Shortcut implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async =>
      HttpResponse.text('blocked', status: 418);
}

void main() {
  late TestApp app;

  Future<TestClient> clientFor(
    HttpModule http,
    List<Route> routes, {
    bool withCall = false,
  }) async {
    app = await TestApp.start(
      root: ProbeRoot(FakeAdapter(), [
        ProbeApi.binding('a', routes),
        if (withCall) ...callBindings(),
      ], http: http),
    );
    return TestClient.of(app);
  }

  tearDown(() => app.close());

  group('middleware', () {
    test('run outermost first around the whole request', () async {
      final events = <String>[];
      final client = await clientFor(
        HttpModule(middleware: [_Header('a', events), _Header('b', events)]),
        [Route.get('/x', (c) => 'ok')],
      );

      final response = await client.get('/x');

      expect(events, ['in a', 'in b', 'out b', 'out a']);
      expect(response.headers['x-a'], 'yes');
      expect(response.headers['x-b'], 'yes');
    });

    test('see requests that match no route', () async {
      final events = <String>[];
      final client = await clientFor(
        HttpModule(middleware: [_Header('a', events)]),
        [Route.get('/x', (c) => 'ok')],
      );

      final response = await client.get('/missing');

      expect(response.status, 404);
      expect(response.headers['x-a'], 'yes');
    });

    test('may answer without calling next', () async {
      final client = await clientFor(HttpModule(middleware: [_Shortcut()]), [
        Route.get('/x', (c) => 'ok'),
      ]);

      expect((await client.get('/x')).status, 418);
    });

    test('a failing middleware is a 500 problem', () async {
      final client = await clientFor(HttpModule(middleware: [_Failing()]), [
        Route.get('/x', (c) => 'ok'),
      ]);

      final response = await client.get('/x');

      expect(response.status, 500);
      expect(response.headers['content-type'], 'application/problem+json');
    });
  });

  group('codecs', () {
    test('a ResponseCodec serializes a type without toJson', () async {
      final client = await clientFor(
        HttpModule(
          codecs: [
            ResponseCodec<_Money>((m) => {'cents': m.cents}),
          ],
        ),
        [Route.get('/m', (c) => const _Money(250))],
      );

      expect((await client.get('/m')).json, {'cents': 250});
    });

    test('a type without a codec is a 500 that names ResponseCodec', () async {
      final client = await clientFor(const HttpModule(), [
        Route.get('/m', (c) => const _Money(250)),
      ]);

      final response = await client.get('/m');

      expect(response.status, 500);
      expect(response.text, isNot(contains('_Money')));
    });
  });

  group('global hooks', () {
    test('wrap every route of every API', () async {
      final client = await clientFor(
        HttpModule(use: [HookRef<UserHook>.type()]),
        [Route.get('/who', (c) => c<CurrentUser>().name)],
        withCall: true,
      );

      final response = await client.get('/who', headers: {'x-user': 'ann'});

      expect(response.text, 'ann');
    });
  });

  group('config', () {
    test('debug shows the error detail of a 500', () async {
      final client = await clientFor(
        const HttpModule(config: HttpConfig(debug: true)),
        [Route.get('/boom', (c) => throw StateError('visible'))],
      );

      final body = (await client.get('/boom')).json as Map;

      expect(body['detail'], contains('visible'));
      expect(body['stack'], isNotNull);
    });

    test('maxBodyBytes limits the body with a 413', () async {
      final client = await clientFor(
        const HttpModule(config: HttpConfig(maxBodyBytes: 8)),
        [Route.post('/p', (c) => c.body((j) => j))],
      );

      final response = await client.post('/p', json: {'long': 'x' * 40});

      expect(response.status, 413);
    });
  });
}
