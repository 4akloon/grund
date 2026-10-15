import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/dispatch_harness.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/log_hook.dart';
import '../helpers/probe_api.dart';

final class _TxThenFail extends HttpHook {
  const _TxThenFail();

  @override
  void before(HttpCtx c) {
    c<Tx>();
    throw StateError('hook failed after the transaction began');
  }
}

void main() {
  final log = <String>[];

  setUp(log.clear);

  test('the handler gets the cancel signal given to dispatch', () async {
    CancelSignal? seen;
    final harness = await DispatchHarness.start([
      ProbeApi.binding('a', [
        Route.get('/', (c) {
          seen = c.cancel;
          return 'ok';
        }),
      ]),
    ]);
    addTearDown(harness.close);
    final cancel = CancelSignal();

    await harness.send('GET', '/', cancel: cancel);

    expect(seen, same(cancel));
  });

  group('hook order', () {
    test(
      'global, API and route hooks wrap the handler in that order',
      () async {
        final harness = await DispatchHarness.start(
          [
            ProbeApi.binding(
              'a',
              [
                Route.get('/', (c) {
                  log.add('handler');
                  return 'ok';
                }, use: [HookRef.instance(LogHook('route', log))]),
              ],
              use: [HookRef.instance(LogHook('api', log))],
            ),
          ],
          global: [HookRef.instance(LogHook('global', log))],
        );
        addTearDown(harness.close);

        await harness.send('GET', '/');

        expect(log, [
          'before global',
          'before api',
          'before route',
          'handler',
          'after route ok',
          'after api ok',
          'after global ok',
        ]);
      },
    );
  });

  group('a failing hook (RF-1)', () {
    Future<DispatchHarness> chainOf(LogHook second, {LogHook? first}) =>
        DispatchHarness.start([
          ProbeApi.binding(
            'a',
            [
              Route.get('/', (c) {
                log.add('handler');
                return 'ok';
              }),
            ],
            use: [
              HookRef.instance(first ?? LogHook('one', log)),
              HookRef.instance(second),
              HookRef.instance(LogHook('three', log)),
            ],
          ),
        ]);

    test(
      'an unexpected error is a 500 without internals and no after',
      () async {
        final harness = await chainOf(
          LogHook('two', log, failBefore: StateError('secret detail')),
        );
        addTearDown(harness.close);

        final response = await harness.send('GET', '/');

        expect(response.status, 500);
        expect(await textOf(response), isNot(contains('secret detail')));
        expect(
          (await jsonOf(response) as Map)['detail'],
          'Internal server error',
        );
        expect(log.where((e) => e.startsWith('after')), isEmpty);
        expect(log, isNot(contains('handler')));
        expect(harness.log.unhandledErrors.single, isA<StateError>());
      },
    );

    test('an HttpException keeps its own status and is not logged', () async {
      final harness = await chainOf(
        LogHook('two', log, failBefore: const ForbiddenException()),
      );
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 403);
      expect(harness.log.unhandledErrors, isEmpty);
    });

    test('onError runs in reverse order; the first answer is sent', () async {
      final harness = await chainOf(
        LogHook('two', log, failBefore: StateError('x')),
        first: LogHook(
          'one',
          log,
          answers: HttpResponse.text('translated', status: 418),
        ),
      );
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 418);
      expect(await textOf(response), 'translated');
      expect(log.where((e) => e.startsWith('onError')), [
        'onError three StateError',
        'onError two StateError',
        'onError one StateError',
      ]);
      expect(harness.log.unhandledErrors, isEmpty);
    });

    test('a hook can translate an error by throwing another', () async {
      final harness = await DispatchHarness.start([
        ProbeApi.binding(
          'a',
          [Route.get('/', (c) => throw ArgumentError('no user 7'))],
          use: [HookRef.instance(_TranslateHook())],
        ),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 404);
      expect((await jsonOf(response) as Map)['detail'], 'No such user');
    });

    test('headers set before the failure stay on the problem', () async {
      final harness = await DispatchHarness.start([
        ProbeApi.binding('a', [
          Route.get('/', (c) {
            c.response.headers.set('x-trace', '42');
            throw const NotFoundException();
          }),
        ]),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 404);
      expect(response.headers['x-trace'], '42');
    });

    test('a hook type that is not provided fails before serving', () async {
      await expectLater(
        DispatchHarness.start([
          ProbeApi.binding(
            'a',
            [Route.get('/', (c) => 1)],
            use: const [HookRef<UserHook>.type()],
          ),
        ]),
        throwsA(isA<MissingProviderError>()),
      );
    });
  });

  group('call scope', () {
    test('a hook hands a value to the handler with c.set', () async {
      final harness = await DispatchHarness.start([
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [Route.get('/', (c) => c<CurrentUser>().name)],
          use: const [HookRef<UserHook>.type()],
        ),
      ]);
      addTearDown(harness.close);

      final response = await harness.send(
        'GET',
        '/',
        headers: {'x-user': 'ann'},
      );

      expect(await textOf(response), 'ann');
    });

    test(
      'concurrent requests do not see each other c.set values (RF-2)',
      () async {
        final gate = Completer<void>();
        final harness = await DispatchHarness.start([
          ...callBindings(),
          ProbeApi.binding(
            'a',
            [
              Route.get('/', (c) async {
                await gate.future;
                return c<CurrentUser>().name;
              }),
            ],
            use: const [HookRef<UserHook>.type()],
          ),
        ]);
        addTearDown(harness.close);

        final ann = harness.send('GET', '/', headers: {'x-user': 'ann'});
        final bob = harness.send('GET', '/', headers: {'x-user': 'bob'});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        gate.complete();

        expect(await textOf(await bob), 'bob');
        expect(await textOf(await ann), 'ann');
      },
    );

    test(
      'a Scoped instance lives for one request and is disposed (RF-2)',
      () async {
        final harness = await DispatchHarness.start([
          ...callBindings(),
          ProbeApi.binding('a', [
            Route.get('/', (c) {
              expect(identical(c<Tx>(), c<Tx>()), isTrue);
              return 'ok';
            }),
          ]),
        ]);
        addTearDown(harness.close);

        await harness.send('GET', '/');
        await harness.send('GET', '/');

        expect(harness<TxLog>().created, 2);
        expect(harness<TxLog>().disposed, 2);
      },
    );

    test('it is disposed when a hook fails after resolving it', () async {
      final harness = await DispatchHarness.start([
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [Route.get('/', (c) => 'ok')],
          use: [HookRef.instance(const _TxThenFail())],
        ),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 500);
      expect(harness<TxLog>().created, 1);
      expect(harness<TxLog>().disposed, 1);
    });

    test('it is disposed also when the handler throws (RF-2)', () async {
      final harness = await DispatchHarness.start([
        ...callBindings(),
        ProbeApi.binding('a', [
          Route.get('/', (c) {
            c<Tx>();
            throw StateError('after the transaction began');
          }),
        ]),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 500);
      expect(harness<TxLog>().created, 1);
      expect(harness<TxLog>().disposed, 1);
    });

    test(
      'a failing dispose is reported, the response is kept (RF-2)',
      () async {
        final harness = await DispatchHarness.start([
          ...callBindings(failOnDispose: true),
          ProbeApi.binding('a', [
            Route.get('/', (c) {
              c<Tx>();
              return 'ok';
            }),
          ]),
        ]);
        addTearDown(harness.close);

        final response = await harness.send('GET', '/');

        expect(response.status, 200);
        expect(harness.log.unhandledErrors.single, isA<ShutdownError>());
      },
    );

    test(
      'a Scoped hook type is created per request, and once to check',
      () async {
        final harness = await DispatchHarness.start([
          Singleton<TxLog>((i) => TxLog(), dependsOn: const []),
          Scoped<CountingHook>(
            (i) => CountingHook(i<TxLog>()),
            dependsOn: const [Key<TxLog>()],
          ),
          ProbeApi.binding(
            'a',
            [Route.get('/', (c) => 'ok')],
            use: const [HookRef<CountingHook>.type()],
          ),
        ]);
        addTearDown(harness.close);
        final afterCheck = harness<TxLog>().created;

        await harness.send('GET', '/');
        await harness.send('GET', '/');

        expect(afterCheck, 1);
        expect(harness<TxLog>().created, 3);
        expect(harness<TxLog>().disposed, 3);
      },
    );
  });
}

/// A hook that counts its own creation.
final class CountingHook extends HttpHook implements Disposable {
  CountingHook(this._log) {
    _log.created++;
  }

  final TxLog _log;

  @override
  void dispose() => _log.disposed++;
}

final class _TranslateHook extends HttpHook {
  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is ArgumentError) {
      throw const NotFoundException(message: 'No such user');
    }
    return null;
  }
}
