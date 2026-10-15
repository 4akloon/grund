import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';

final class _NoAdapterRoot extends Module {
  @override
  List<Module> get imports => const [HttpModule()];
}

final class _MissingHook extends HttpHook {
  const _MissingHook();
}

Binding<Object> _api(String name, String path) =>
    ProbeApi.binding(name, [Route.get(path, (c) => 'ok')]);

void main() {
  late FakeAdapter adapter;

  setUp(() => adapter = FakeAdapter());

  App appWith(
    List<Binding<Object>> bindings, {
    HttpModule http = const HttpModule(
      config: HttpConfig(address: '127.0.0.1', port: 0),
    ),
  }) => App(root: ProbeRoot(adapter, bindings, http: http));

  group('start', () {
    test('hands the handler, address and port to the adapter', () async {
      final app = appWith([
        _api('a', '/x'),
      ], http: const HttpModule(config: HttpConfig(address: 'h', port: 7)));
      await app.start();
      addTearDown(app.close);

      expect(adapter.address, 'h');
      expect(adapter.port, 7);
      expect((await adapter.send(requestFor('GET', '/x'))).status, 200);
    });

    test('only an empty set does not listen but builds the routes', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start(only: const {});
      addTearDown(app.close);

      expect(adapter.handler, isNull);
      expect(serverOf(app).routes, ['GET /x']);
    });
  });

  group('startup failures (RF-4)', () {
    test('a duplicate route across APIs fails before listen', () async {
      final app = appWith([_api('a', '/x'), _api('b', '/x')]);

      await expectLater(app.start(), throwsA(isA<GrundError>()));

      expect(adapter.handler, isNull);
      expect(app.isClosed, isTrue);
    });

    test('a missing adapter is a MissingProviderError naming it', () async {
      final app = App(root: _NoAdapterRoot());

      await expectLater(
        app.start(),
        throwsA(
          isA<MissingProviderError>().having(
            (e) => e.toString(),
            'message',
            contains('HttpAdapter'),
          ),
        ),
      );
    });

    test('an unknown runner in only is an UnknownRunnerError', () async {
      final app = appWith([_api('a', '/x')]);

      await expectLater(
        app.start(only: const {'htpp'}),
        throwsA(
          isA<UnknownRunnerError>().having(
            (e) => e.available,
            'available',
            contains('http'),
          ),
        ),
      );
    });

    test('a listen failure is a RunnerError and closes the app', () async {
      adapter.listenFailure = StateError('port in use');
      final app = appWith([_api('a', '/x')]);

      await expectLater(
        app.start(),
        throwsA(
          isA<RunnerError>()
              .having((e) => e.runner, 'runner', 'http')
              .having((e) => e.phase, 'phase', 'start'),
        ),
      );

      expect(app.isClosed, isTrue);
    });

    test('a hook that cannot be resolved fails before listen', () async {
      final app = appWith([
        ProbeApi.binding(
          'a',
          [Route.get('/x', (c) => 'ok')],
          use: [HookRef<_MissingHook>.type()],
        ),
      ]);

      await expectLater(app.start(), throwsA(isA<GrundError>()));

      expect(adapter.handler, isNull);
    });
  });

  group('close (RF-5)', () {
    test('is idempotent and closes the adapter once', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start();

      await app.close();
      await app.close();

      expect(adapter.closeCalls, hasLength(1));
    });

    test('does not close an adapter that never listened', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start(only: const {});

      await app.close();

      expect(adapter.closeCalls, isEmpty);
    });

    test('waits for requests in flight, new ones get 503', () async {
      final gate = Completer<void>();
      final app = appWith([
        ProbeApi.binding('a', [
          Route.get('/slow', (c) async {
            await gate.future;
            return 'done';
          }),
        ]),
      ]);
      await app.start(only: const {});
      final server = serverOf(app);
      final slow = server.handle(requestFor('GET', '/slow'));
      await pumpEventQueue();

      final closing = app.close();
      await pumpEventQueue();
      final late = await server.handle(requestFor('GET', '/slow'));
      var closed = false;
      unawaited(closing.then((_) => closed = true));
      await pumpEventQueue();

      expect(late.status, 503);
      expect((await jsonOf(late) as Map)['code'], 'server_unavailable');
      expect(closed, isFalse);
      gate.complete();
      expect((await slow).status, 200);
      await closing;
    });

    test('a request from the adapter does not block close and is '
        'cancelled', () async {
      final seen = Completer<CancelSignal>();
      final hang = Completer<void>();
      final app = appWith([
        ProbeApi.binding('a', [
          Route.get('/hang', (c) async {
            seen.complete(c.cancel);
            await hang.future;
            return 'late';
          }),
        ]),
      ]);
      await app.start();
      final pending = adapter.send(requestFor('GET', '/hang'));
      final cancel = await seen.future;

      await app.close().timeout(const Duration(seconds: 5));
      await cancel.whenCancelled;
      hang.complete();

      expect(cancel.isCancelled, isTrue);
      expect((await pending).status, 200);
    });

    test('a request from the adapter after close gets 503', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start();
      await app.close();

      final response = await adapter.send(requestFor('GET', '/x'));

      expect(response.status, 503);
    });

    test(
      'an adapter close failure is a ShutdownError, the rest closes',
      () async {
        adapter.closeFailure = StateError('stuck');
        final app = appWith([_api('a', '/x')]);
        await app.start();

        await expectLater(app.close(), throwsA(isA<ShutdownError>()));

        expect(app.isClosed, isTrue);
      },
    );
  });
}
