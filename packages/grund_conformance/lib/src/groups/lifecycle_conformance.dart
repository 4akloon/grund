import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../conformance_probe.dart';
import '../conformance_root.dart';
import '../conformance_server.dart';
import '../raw_http.dart';

/// Closing, failures and misbehaving clients: the adapter finishes or
/// drops in-flight work as asked, releases its port, and keeps serving
/// after anything a single request does.
abstract final class LifecycleConformance {
  /// How long a test waits for a step the adapter must make on its own.
  static const stepTimeout = Duration(seconds: 5);

  /// How long a test watches that something does not happen.
  static const settle = Duration(milliseconds: 200);

  /// The adapter's `closeTimeout` in the tests that let it expire.
  static const shortCloseTimeout = Duration(milliseconds: 250);

  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('lifecycle', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      // Replaces the server with one whose adapter has [closeTimeout].
      Future<void> restart({
        Duration? closeTimeout = ConformanceServer.defaultCloseTimeout,
        ErrorLog? errorLog,
      }) async {
        await server.close();
        server = await ConformanceServer.start(
          factory,
          closeTimeout: closeTimeout,
          errorLog: errorLog,
        );
      }

      Future<void> expectPortFree() async {
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        await rebound.close();
      }

      // Holds a slow request, checks close waits for it, then lets it end.
      Future<void> expectCloseWaitsForSlowHandler() async {
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      }

      test('close waits for a response that is still streaming', () async {
        final request = await server.client.get(
          '127.0.0.1',
          server.port,
          '/probe/gated-stream',
        );
        final response = await request.close().timeout(stepTimeout);
        final body = utf8.decoder.bind(response).join();
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect(await body, 'first;last');
        await closing.timeout(stepTimeout);
      });

      test('close waits for a slow handler', () async {
        await expectCloseWaitsForSlowHandler();
      });

      test('close refuses new connections and releases the port', () async {
        await server.app.close().timeout(stepTimeout);

        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, server.port),
          throwsA(isA<SocketException>()),
        );
        await expectPortFree();
      });

      test('force close drops a request in flight', () async {
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);

        await server.adapter.close(force: true).timeout(stepTimeout);

        await expectLater(response, throwsA(isA<IOException>()));
      });

      // Review Focus 6: the adapter drops the connection after the timeout
      // and App.close does not wait for the abandoned handler.
      test('close gives up on a stuck handler after closeTimeout', () async {
        await restart(closeTimeout: shortCloseTimeout);
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        final stopwatch = Stopwatch()..start();

        await server.app.close().timeout(stepTimeout);

        expect(stopwatch.elapsed, greaterThan(shortCloseTimeout ~/ 2));
        await expectLater(response, throwsA(isA<IOException>()));
        await expectPortFree();
      });

      test('close cuts a streaming response after closeTimeout', () async {
        await restart(closeTimeout: shortCloseTimeout);
        final streamed = RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/gated-stream'),
        );
        await server.probe.entered.future.timeout(stepTimeout);

        await server.app.close().timeout(stepTimeout);

        final response = await streamed;
        expect((response.status, response.isComplete), (200, false));
      });

      test('close lets a handler that finishes in time answer', () async {
        await restart(closeTimeout: shortCloseTimeout);
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        final closing = server.app.close();

        server.probe.release.complete();

        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      });

      test('close without a closeTimeout waits for a slow handler', () async {
        await restart(closeTimeout: null);
        await expectCloseWaitsForSlowHandler();
      });

      test('answers 500 without a body when the ErrorLog throws', () async {
        await restart(errorLog: const _ThrowingErrorLog());

        final failed = await server.send('GET', '/probe/fail');
        final next = await server.send('GET', '/users/1');

        expect(failed.status, 500);
        expect(failed.bytes, isEmpty);
        expect(
          await server.firstAdapterError.timeout(stepTimeout),
          isA<StateError>(),
        );
        expect(next.status, 200);
      });

      test('aborts the connection when the body stream fails', () async {
        final broken = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/broken-stream'),
        );
        final next = await server.send('GET', '/users/1');

        expect(broken.isComplete, isFalse);
        expect(
          await server.firstAdapterError.timeout(stepTimeout),
          isA<StateError>(),
        );
        expect(next.status, 200);
      });

      test('close completes after a body stream failed', () async {
        await restart(closeTimeout: null);
        await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/broken-stream'),
        );
        await server.firstAdapterError.timeout(stepTimeout);

        await server.app.close().timeout(stepTimeout);
      });

      for (final route in const ['bad-header', 'bad-length']) {
        test('a response whose head cannot be written is reported and the '
            'connection closes ($route)', () async {
          // The client sees the connection closed, with or without a head.
          await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', '/probe/$route'),
          );
          await server.firstAdapterError.timeout(stepTimeout);
          await server.app.close().timeout(stepTimeout);
          await expectLater(
            Socket.connect(InternetAddress.loopbackIPv4, server.port),
            throwsA(isA<SocketException>()),
          );
        });
      }

      test(
        'a failed bind fails the start; another application serves',
        () async {
          final blocker = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(blocker.close);
          final app = App(
            root: ConformanceRoot(
              ConformanceProbe(),
              adapter: factory((_, _) {}, null).module,
              port: blocker.port,
            ),
          );

          await expectLater(
            app.start(),
            throwsA(
              isA<RunnerError>().having(
                (error) => error.error,
                'error',
                isA<SocketException>(),
              ),
            ),
          );
          final next = await ConformanceServer.start(factory);
          addTearDown(next.close);

          expect(app.isClosed, isTrue);
          expect((await next.send('GET', '/users/1')).status, 200);
        },
      );

      // Review Focus 4: the stream is cancelled and close is not stuck.
      test('survives a client that leaves mid-response', () async {
        await RawHttp.abortAfterFirstBytes(
          server.port,
          RawHttp.head('GET', '/probe/endless'),
        );

        await server.probe.endlessCancelled.future.timeout(stepTimeout);
        expect((await server.send('GET', '/users/1')).status, 200);
        await server.app.close().timeout(stepTimeout);
      });
    });
  }
}

/// An error log that fails, to prove the adapter survives it.
final class _ThrowingErrorLog implements ErrorLog {
  const _ThrowingErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) =>
      throw StateError('log failed');
}
