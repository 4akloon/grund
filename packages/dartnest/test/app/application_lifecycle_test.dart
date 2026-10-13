import 'dart:async';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';

final class Waiter {
  Waiter(this.gate);
  final Completer<void> gate;
}

Module waitingModule(Completer<void> gate) => Module(
  id: 'app',
  controllers: [
    Controller<Waiter>(
      create: (i) => Waiter(gate),
      routes: [
        Route.get('/wait', (c, ctx) async {
          await c.gate.future;
          return 'done';
        }),
      ],
    ),
  ],
);

void main() {
  group('Application.listen', () {
    test('hands handle, address and port to the adapter', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);

      await app.listen(port: 0);

      expect(adapter.address, 'localhost');
      expect(adapter.port, 0);
      final response = await adapter.send(requestFor('GET', '/users/1'));
      expect(response.status, 200);
    });

    test(
      'rejects a missing adapter, a second listen and a closed app',
      () async {
        final bare = await Application.create(appModule);
        expect(
          () => bare.listen(port: 0),
          throwsA(
            isA<ApplicationStateError>().having(
              (e) => e.message,
              'message',
              'Cannot listen: no HttpAdapter was passed to Application.create.',
            ),
          ),
        );

        final app = await Application.create(appModule, adapter: FakeAdapter());
        await app.listen(port: 0);
        expect(
          () => app.listen(port: 0),
          throwsA(isA<ApplicationStateError>()),
        );

        final closed = await Application.create(
          appModule,
          adapter: FakeAdapter(),
        );
        await closed.close();
        expect(
          () => closed.listen(port: 0),
          throwsA(isA<ApplicationStateError>()),
        );
      },
    );

    test('a failed listen can be retried', () async {
      final adapter = FakeAdapter()..listenFailure = StateError('port in use');
      final app = await Application.create(appModule, adapter: adapter);

      await expectLater(app.listen(port: 80), throwsStateError);
      await app.listen(port: 8080);

      expect(adapter.port, 8080);
    });

    test('state errors are failed futures, not synchronous throws', () async {
      final bare = await Application.create(appModule);

      final result = bare.listen(port: 0);

      await expectLater(result, throwsA(isA<ApplicationStateError>()));
    });
  });

  // Review Focus 5: close is repeatable and graceful.
  group('Application.close', () {
    test('is idempotent and closes the adapter and container once', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);
      await app.listen(port: 0);

      final first = app.close(force: true);
      final second = app.close();
      await first;

      expect(identical(first, second), isTrue);
      expect(adapter.closeCalls, [true]);
      expect(app.isClosed, isTrue);
      expect(app.container.isClosed, isTrue);
    });

    test('does not close an adapter that never listened', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);

      await app.close();

      expect(adapter.closeCalls, isEmpty);
    });

    test('waits for in-flight requests, new ones get 503', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => waitingModule(gate));
      final inFlight = app.handle(requestFor('GET', '/wait'));

      var closed = false;
      final closing = app.close().then((_) => closed = true);
      await pumpEventQueue();

      expect(closed, isFalse);
      expect((await app.handle(requestFor('GET', '/wait'))).status, 503);

      gate.complete();
      expect((await inFlight).status, 200);
      await closing;
      expect(closed, isTrue);
    });

    test('force does not wait for in-flight requests', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => waitingModule(gate));
      unawaited(app.handle(requestFor('GET', '/wait')));

      await app.close(force: true);

      expect(app.container.isClosed, isTrue);
      gate.complete();
    });
  });

  test('use after close fails with ApplicationStateError', () async {
    final app = await Application.create(appModule);
    final closing = app.close();

    expect(
      () => app.use((request, next) => next()),
      throwsA(
        isA<ApplicationStateError>().having(
          (e) => e.operation,
          'operation',
          'use',
        ),
      ),
    );
    await closing;
  });

  test('closes the container even when the adapter close throws', () async {
    final adapter = FakeAdapter()..closeFailure = StateError('close failed');
    final app = await Application.create(appModule, adapter: adapter);
    await app.listen(port: 0);

    final first = app.close();
    final second = app.close();

    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(app.container.isClosed, isTrue);
  });

  group('Container.close', () {
    test('is idempotent', () async {
      final container = await Container.create(Module(id: 'app'));

      expect(container.isClosed, isFalse);
      final first = container.close();
      expect(identical(first, container.close()), isTrue);
      expect(container.isClosed, isTrue);
    });
  });
}
