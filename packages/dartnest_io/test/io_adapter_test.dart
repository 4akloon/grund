import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:test/test.dart';

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

    test('listens only once', () async {
      final adapter = IoAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);

      await expectLater(
        adapter.listen(
          answerOk,
          address: io.InternetAddress.loopbackIPv4,
          port: 0,
        ),
        throwsStateError,
      );
    });

    test('close before listen completes and blocks a later listen', () async {
      final adapter = IoAdapter();

      await adapter.close();

      await expectLater(
        adapter.listen(
          answerOk,
          address: io.InternetAddress.loopbackIPv4,
          port: 0,
        ),
        throwsStateError,
      );
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

    test('a second concurrent listen throws and leaks no server', () async {
      final adapter = IoAdapter();
      addTearDown(adapter.close);

      final first = adapter.listen(answerOk, address: loopback, port: 0);
      final second = adapter.listen(answerOk, address: loopback, port: 0);

      await expectLater(second, throwsStateError);
      await first;
      final port = adapter.port;
      await adapter.close();
      await expectPortFree(port);
    });

    test('close during bind closes the server and fails listen', () async {
      final port = await freePort();
      final adapter = IoAdapter();

      final listening = adapter.listen(answerOk, address: loopback, port: port);
      final listenResult = expectLater(listening, throwsStateError);
      await adapter.close();

      await listenResult;
      await expectPortFree(port);
    });
  });
}
