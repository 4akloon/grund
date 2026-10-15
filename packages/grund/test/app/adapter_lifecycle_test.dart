import 'dart:async';

import 'package:grund/adapter.dart';
import 'package:test/test.dart';

/// A server that records how it was stopped; with [holdsGracefulStop] a
/// graceful stop only ends once a forced one was requested, like an
/// `HttpServer` with open connections.
final class _FakeServer {
  _FakeServer({this.holdsGracefulStop = false});

  final bool holdsGracefulStop;
  final List<bool> stops = [];
  final Completer<void> _connectionsDropped = Completer<void>();

  Future<void> stop({required bool force}) {
    stops.add(force);
    if (force && !_connectionsDropped.isCompleted) {
      _connectionsDropped.complete();
    }
    if (force || !holdsGracefulStop) return Future.value();
    return _connectionsDropped.future;
  }
}

/// A lifecycle whose server is [server] and which serves nothing.
final class _Harness {
  _Harness(this.server, {Duration? closeTimeout})
    : lifecycle = AdapterLifecycle(name: 'Fake', closeTimeout: closeTimeout);

  final _FakeServer server;
  final AdapterLifecycle<_FakeServer> lifecycle;
  int served = 0;

  Future<void> start({Future<_FakeServer> Function()? bind}) => lifecycle.start(
    bind ?? () async => server,
    stop: (server, {required force}) => server.stop(force: force),
    serve: (_) => served++,
  );
}

void main() {
  group('AdapterLifecycle', () {
    test('listens only once', () async {
      final harness = _Harness(_FakeServer());
      await harness.start();

      await expectLater(
        harness.start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Fake.listen can be called only once.',
          ),
        ),
      );
      expect(harness.served, 1);
    });

    test('a failed bind can be retried', () async {
      final harness = _Harness(_FakeServer());
      var attempts = 0;
      Future<_FakeServer> bindOnce() async {
        if (attempts++ == 0) throw StateError('address in use');
        return harness.server;
      }

      await expectLater(
        harness.start(bind: bindOnce),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'address in use',
          ),
        ),
      );
      await harness.start(bind: bindOnce);

      expect(harness.lifecycle.server, same(harness.server));
      expect(harness.served, 1);
      await harness.lifecycle.close(force: false);
      expect(harness.server.stops, [false]);
    });

    test('close before listen completes and blocks a later listen', () async {
      final harness = _Harness(_FakeServer());

      await harness.lifecycle.close(force: false);

      await expectLater(
        harness.start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Fake is closed.',
          ),
        ),
      );
      expect(harness.server.stops, isEmpty);
    });

    test('close is idempotent and forgets the server', () async {
      final harness = _Harness(_FakeServer());
      await harness.start();
      expect(harness.lifecycle.server, same(harness.server));

      final lifecycle = harness.lifecycle;
      expect(
        identical(lifecycle.close(force: false), lifecycle.close(force: false)),
        isTrue,
      );
      await lifecycle.close(force: false);

      expect(lifecycle.server, isNull);
      expect(harness.server.stops, [false]);
    });

    test('a second concurrent listen throws and leaks no server', () async {
      final harness = _Harness(_FakeServer());
      final bind = Completer<_FakeServer>();

      final first = harness.start(bind: () => bind.future);
      final second = harness.start();

      await expectLater(second, throwsStateError);
      bind.complete(harness.server);
      await first;
      await harness.lifecycle.close(force: false);
      expect(harness.served, 1);
      expect(harness.server.stops, [false]);
    });

    test('close during bind closes the server and fails listen', () async {
      final harness = _Harness(_FakeServer());
      final bind = Completer<_FakeServer>();

      final listening = harness.start(bind: () => bind.future);
      final listenResult = expectLater(
        listening,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Fake was closed while binding.',
          ),
        ),
      );
      final closing = harness.lifecycle.close(force: false);
      bind.complete(harness.server);

      await listenResult;
      await closing;
      expect(harness.server.stops, [true]);
      expect(harness.served, 0);
    });

    test('close(force: true) escalates a pending graceful close', () async {
      final harness = _Harness(_FakeServer(holdsGracefulStop: true));
      await harness.start();
      final graceful = harness.lifecycle.close(force: false);
      await Future<void>.delayed(Duration.zero);

      await harness.lifecycle
          .close(force: true)
          .timeout(const Duration(seconds: 5));

      await graceful.timeout(const Duration(seconds: 5));
      expect(harness.server.stops, [false, true]);
    });

    test('a failing forced stop surfaces through the pending close', () async {
      final gate = Completer<void>();
      final lifecycle = AdapterLifecycle<_FakeServer>(
        name: 'Fake',
        closeTimeout: null,
      );
      await lifecycle.start(
        () async => _FakeServer(),
        stop: (server, {required force}) =>
            force ? Future.error(StateError('stop failed')) : gate.future,
        serve: (_) {},
      );
      final graceful = lifecycle.close(force: false);
      final failure = expectLater(graceful, throwsStateError);

      unawaited(lifecycle.close(force: true).catchError((Object _) {}));
      gate.complete();

      await failure;
    });

    test('a graceful close waits for the requests in flight', () async {
      final harness = _Harness(_FakeServer());
      await harness.start();
      final release = Completer<void>();
      unawaited(harness.lifecycle.inFlight.track(() => release.future));
      var closed = false;
      final closing = harness.lifecycle
          .close(force: false)
          .then((_) => closed = true);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(closed, isFalse);
      release.complete();

      await closing;
      expect(harness.server.stops, [false]);
    });

    test('a graceful close gives up after closeTimeout', () async {
      final harness = _Harness(
        _FakeServer(),
        closeTimeout: const Duration(milliseconds: 50),
      );
      await harness.start();
      final release = Completer<void>();
      addTearDown(() => release.isCompleted ? null : release.complete());
      unawaited(harness.lifecycle.inFlight.track(() => release.future));

      await harness.lifecycle.close(force: false);

      expect(harness.server.stops, [false, true]);
    });
  });
}
