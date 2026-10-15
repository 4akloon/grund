import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:test/test.dart';

import 'helpers/shelf_adapter_support.dart';

void main() {
  group('ShelfAdapter', () {
    test('has no port before listen', () {
      expect(() => ShelfAdapter().port, throwsStateError);
    });

    test('serves on the bound ephemeral port', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(answerOk, address: loopback, port: 0);
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await getRoot(client, adapter.port);

      expect(response.statusCode, 200);
      expect(await response.map(String.fromCharCodes).join(), 'ok');
    });

    test('close is idempotent and forgets the port', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(answerOk, address: loopback, port: 0);

      expect(identical(adapter.close(), adapter.close()), isTrue);
      await adapter.close();
      expect(() => adapter.port, throwsStateError);
    });

    test('sends no x-powered-by and no dart:io default headers', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(answerOk, address: loopback, port: 0);
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await getRoot(client, adapter.port);

      expect(response.headers.value('x-powered-by'), isNull);
      expect(response.headers.value('x-frame-options'), isNull);
      expect(response.headers.value('x-content-type-options'), isNull);
    });

    test('answers 500 without a body when the handler throws', () async {
      final errors = <Object>[];
      final adapter = ShelfAdapter(onError: (error, _) => errors.add(error));
      await adapter.listen(
        (request) async => throw StateError('handler failed'),
        address: loopback,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await getRoot(client, adapter.port);

      expect(response.statusCode, 500);
      expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(errors, [isA<StateError>()]);
    });

    test('answers 500 and keeps serving when onError throws', () async {
      var fail = true;
      final adapter = ShelfAdapter(onError: (_, _) => throw StateError('log'));
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

      final failed = await statusOf(client, adapter.port);
      fail = false;
      final next = await statusOf(client, adapter.port);

      expect((failed, next), (500, 200));
    });

    test('a failing body stream is reported and does not leak', () async {
      final errors = <Object>[];
      final adapter = ShelfAdapter(
        onError: (error, _) => errors.add(error),
        closeTimeout: null,
      );
      await adapter.listen(
        (request) async => HttpResponse.stream(
          Stream<List<int>>.multi((controller) {
            controller.add([111, 107]);
            controller.addError(StateError('body failed'));
            controller.close();
          }),
        ),
        address: loopback,
        port: 0,
      );
      final client = io.HttpClient();
      addTearDown(() => client.close(force: true));

      await getRoot(
        client,
        adapter.port,
      ).then((r) => r.drain<void>()).then((_) {}, onError: (Object _) {});

      await adapter.close().timeout(const Duration(seconds: 5));
      expect(errors, isNotEmpty);
    });
  });
}
