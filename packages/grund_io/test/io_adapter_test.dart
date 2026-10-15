import 'dart:async';
import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

import 'helpers/captured_stderr.dart';

/// Answers every request with `ok`.
Future<HttpResponse> answerOk(HttpRequest request) async =>
    HttpResponse.text('ok');

final loopback = io.InternetAddress.loopbackIPv4;

/// A port nothing listens on right now.
Future<int> freePort() async {
  final socket = await io.ServerSocket.bind(loopback, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Fails unless [port] can be bound, i.e. no server holds it.
Future<void> expectPortFree(int port) async {
  final socket = await io.ServerSocket.bind(loopback, port);
  await socket.close();
}

void main() {
  group('IoAdapter', () {
    test('has no port before listen', () {
      expect(() => IoAdapter().port, throwsStateError);
    });

    test('serves on the bound ephemeral port', () async {
      final adapter = IoAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final request = await client.get('127.0.0.1', adapter.port, '/');
      final response = await request.close();

      expect(response.statusCode, 200);
      expect(await response.map(String.fromCharCodes).join(), 'ok');
    });

    test('close is idempotent and forgets the port', () async {
      final adapter = IoAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );

      expect(identical(adapter.close(), adapter.close()), isTrue);
      await adapter.close();
      expect(() => adapter.port, throwsStateError);
    });

    test('answers 500 without a body when the handler throws', () async {
      final errors = <Object>[];
      final adapter = IoAdapter(onError: (error, _) => errors.add(error));
      await adapter.listen(
        (request) async => throw StateError('handler failed'),
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await (await client.get(
        '127.0.0.1',
        adapter.port,
        '/',
      )).close();

      expect(response.statusCode, 500);
      expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(errors, [isA<StateError>()]);
    });

    test('answers 500 and keeps serving when onError throws', () async {
      var fail = true;
      final adapter = IoAdapter(onError: (_, _) => throw StateError('log'));
      await adapter.listen(
        (request) async {
          if (fail) throw StateError('handler failed');
          return HttpResponse.text('ok');
        },
        address: loopback,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);
      Future<int> status() async => (await (await client.get(
        '127.0.0.1',
        adapter.port,
        '/',
      )).close()).statusCode;

      final failed = await status();
      fail = false;
      final next = await status();

      expect((failed, next), (500, 200));
    });

    test('writes a failing onError with its stack trace to stderr', () async {
      final written = await captureStderr(() async {
        final adapter = IoAdapter(
          onError: (_, _) => throw StateError('reporter failed'),
        );
        await adapter.listen(
          (request) async => throw StateError('handler failed'),
          address: loopback,
          port: 0,
        );
        final client = io.HttpClient();
        try {
          await (await client.get('127.0.0.1', adapter.port, '/')).close();
        } finally {
          client.close();
          await adapter.close(force: true);
        }
      });

      expect(written, contains('onError failed: Bad state: reporter failed'));
      expect(written, contains('io_adapter_test.dart'));
    });
  });
}
