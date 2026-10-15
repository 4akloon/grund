import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/server/server_log.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/log_capture.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';

final class _Code {
  static var paths = <String>['/old'];
}

final class _EditableApi extends HttpApi {
  _EditableApi(super.injector);

  @override
  List<Route> get routes => [
    for (final path in _Code.paths) Route.get(path, (c) => path),
  ];
}

void main() {
  late FakeAdapter adapter;
  late LogCapture capture;

  setUp(() {
    adapter = FakeAdapter();
    capture = LogCapture.start();
  });

  Future<App> started(
    List<Binding<Object>> bindings, {
    HttpConfig config = const HttpConfig(port: 0),
  }) async {
    final app = App(
      root: ProbeRoot(adapter, bindings, http: HttpModule(config: config)),
    );
    await app.start();
    addTearDown(app.close);
    return app;
  }

  Binding<Object> api(List<Route> routes) => ProbeApi.binding('probe', routes);

  group('route and server messages', () {
    test('mapped routes are logged sorted by path, then method', () async {
      await started([
        api([
          Route.get('/b', (c) => 'b'),
          Route.post('/a', (c) => 'a'),
          Route.get('/a', (c) => 'a'),
        ]),
      ]);

      expect(await capture.messages('grund.routes'), [
        'Mapped {GET, /a}',
        'Mapped {POST, /a}',
        'Mapped {GET, /b}',
      ]);
    });

    test('the listening address follows the listen', () async {
      await started([
        api(const []),
      ], config: const HttpConfig(address: 'host', port: 7));

      expect(await capture.messages('grund.http'), [
        'HTTP server listening on host:7',
      ]);
    });

    test('an application that does not listen logs no listener', () async {
      final app = App(root: ProbeRoot(adapter, [api(const [])]));
      await app.start(only: const {});
      await app.close();

      expect(await capture.messages('grund.http'), isEmpty);
    });

    test('stop logs that the server closed', () async {
      final app = await started([api(const [])]);

      await app.close();

      expect(
        (await capture.messages('grund.http')).last,
        ServerLog.closedMessage,
      );
    });

    test('a reassemble logs added and removed routes', () async {
      _Code.paths = ['/old'];
      final app = await started([
        Singleton<_EditableApi>(
          (i) => _EditableApi(i),
          name: 'editable',
          dependsOn: const [],
        ),
      ]);
      _Code.paths = ['/new'];

      await app.reassemble();

      expect(await capture.messages('grund.routes'), [
        'Mapped {GET, /old}',
        'Mapped {GET, /new}',
        'Unmapped {GET, /old}',
      ]);
    });
  });

  group('access log', () {
    Future<List<String>> accessAfter(HttpRequest request) async {
      await started([
        api([
          Route.get('/ok', (c) => 'ok'),
          Route.get('/boom', (c) => throw StateError('boom')),
        ]),
      ]);
      await adapter.send(request);
      return capture.messages('grund.access');
    }

    test('a 200 is logged with method, path and time', () async {
      expect(await accessAfter(requestFor('GET', '/ok')), [
        matches(r'^GET /ok 200 \d+ms$'),
      ]);
    });

    test('the query string is not logged', () async {
      expect(await accessAfter(requestFor('GET', '/ok?token=secret')), [
        matches(r'^GET /ok 200 \d+ms$'),
      ]);
    });

    test('a 404 is logged', () async {
      expect(await accessAfter(requestFor('GET', '/missing')), [
        matches(r'^GET /missing 404 \d+ms$'),
      ]);
    });

    test('a 405 is logged', () async {
      expect(await accessAfter(requestFor('DELETE', '/ok')), [
        matches(r'^DELETE /ok 405 \d+ms$'),
      ]);
    });

    test('a problem response is logged', () async {
      expect(await accessAfter(requestFor('GET', '/boom')), [
        matches(r'^GET /boom 500 \d+ms$'),
      ]);
    });

    test('the 503 while closing is logged', () async {
      final server = serverOf(await started([api(const [])]));
      await server.stop();

      final response = await server.handle(requestFor('GET', '/x'));

      expect(response.status, 503);
      expect(await capture.messages('grund.access'), [
        matches(r'^GET /x 503 \d+ms$'),
      ]);
    });

    test('accessLog false logs nothing', () async {
      await started([
        api([Route.get('/ok', (c) => 'ok')]),
      ], config: const HttpConfig(port: 0, accessLog: false));

      await adapter.send(requestFor('GET', '/ok'));

      expect(await capture.messages('grund.access'), isEmpty);
    });
  });

  group('unhandled errors', () {
    test(
      'logs a SEVERE record with error and stack, body leaks nothing',
      () async {
        await started([
          api([Route.get('/boom', (c) => throw StateError('secret detail'))]),
        ]);

        final response = await adapter.send(requestFor('GET', '/boom'));
        await capture.messages('grund.http');

        final severe = capture.records.singleWhere(
          (r) => r.level == Level.SEVERE,
        );
        expect(severe.loggerName, 'grund.http');
        expect(severe.error, isA<StateError>());
        expect(severe.stackTrace, isNotNull);
        expect(response.status, 500);
        expect(await textOf(response), isNot(contains('secret detail')));
      },
    );
  });
}
