import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:test/test.dart';

/// Answers every request with `ok`.
Future<HttpResponse> answerOk(HttpRequest request) async =>
    HttpResponse.text('ok');

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
  });
}
