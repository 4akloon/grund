import 'dart:convert';
import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// The user's own shelf stack: a middleware that tags every response, an
/// own route, and the grund application mounted under `/api/`.
shelf.Handler userPipeline(shelf.Handler api) => const shelf.Pipeline()
    .addMiddleware(
      (inner) =>
          (request) async =>
              (await inner(request)).change(headers: {'x-user-stack': 'yes'}),
    )
    .addHandler(
      shelf.Cascade()
          .add(
            (request) => request.url.path == 'health'
                ? shelf.Response.ok('healthy')
                : shelf.Response.notFound(null),
          )
          .add(
            (request) => request.url.path.startsWith('api/')
                ? api(request.change(path: 'api'))
                : shelf.Response.notFound(null),
          )
          .handler,
    );

void main() {
  group('shelfHandler', () {
    late App app; // Set in setUp before every test.

    // The application only prepares its routes: no port is opened.
    Future<App> startApp({List<Binding<Object>> overrides = const []}) async {
      final app = App(
        root: ConformanceRoot(
          ConformanceProbe(),
          adapter: const ShelfAdapterModule(),
        ),
        overrides: overrides,
      );
      await app.start(only: const {});
      addTearDown(app.close);
      return app;
    }

    setUp(() async => app = await startApp());

    test('answers inside a user pipeline, mounted under a prefix', () async {
      final server = await shelf_io.serve(
        userPipeline(shelfHandler(app)),
        io.InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      Future<(int, String?, String)> get(String path) async {
        final response = await (await client.get(
          '127.0.0.1',
          server.port,
          path,
        )).close();
        return (
          response.statusCode,
          response.headers.value('x-user-stack'),
          await utf8.decoder.bind(response).join(),
        );
      }

      expect(await get('/api/users/1'), (
        200,
        'yes',
        jsonEncode({'id': 1, 'name': 'ann'}),
      ));
      expect(await get('/health'), (200, 'yes', 'healthy'));
    });

    test('answers 503 after the application is closed', () async {
      final handler = shelfHandler(app);
      await app.close();

      final response = await handler(
        shelf.Request('GET', Uri.parse('http://localhost/users/1')),
      );

      expect(response.statusCode, 503);
    });

    test('refuses an application that is not started', () {
      final idle = App(
        root: ConformanceRoot(
          ConformanceProbe(),
          adapter: const ShelfAdapterModule(),
        ),
      );

      expect(() => shelfHandler(idle), throwsA(isA<ApplicationStateError>()));
    });

    Future<App> failingLogApp() => startApp(
      overrides: [
        Singleton<ErrorLog>(
          (_) => const _ThrowingErrorLog(),
          dependsOn: const [],
        ),
      ],
    );

    // A function: a request body can be read only once.
    shelf.Request failRequest() =>
        shelf.Request('GET', Uri.parse('http://localhost/probe/fail'));

    test('answers 500 without a body when the ErrorLog throws', () async {
      final errors = <Object>[];

      final response = await shelfHandler(
        await failingLogApp(),
        onError: (error, _) => errors.add(error),
      )(failRequest());

      expect(response.statusCode, 500);
      expect(await response.readAsString(), isEmpty);
      expect(errors, [isA<StateError>()]);
    });

    test('answers 500 even when its own onError throws', () async {
      final response = await shelfHandler(
        await failingLogApp(),
        onError: (error, _) => throw StateError('reporter failed'),
      )(failRequest());

      expect(response.statusCode, 500);
    });

    test('drops the body of a HEAD response', () async {
      final response = await shelfHandler(app)(
        shelf.Request('HEAD', Uri.parse('http://localhost/users/1')),
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['content-length'],
        '${jsonEncode({'id': 1, 'name': 'ann'}).length}',
      );
      expect(await response.readAsString(), isEmpty);
    });
  });
}

/// An error log that fails, to prove the handler survives it.
final class _ThrowingErrorLog implements ErrorLog {
  const _ThrowingErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) =>
      throw StateError('log failed');
}
