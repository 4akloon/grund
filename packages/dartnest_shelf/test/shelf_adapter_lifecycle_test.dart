import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:test/test.dart';

import 'shelf_adapter_support.dart';

void main() {
  group('ShelfAdapter lifecycle', () {
    test('listens only once', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(answerOk, address: loopback, port: 0);
      addTearDown(adapter.close);

      await expectLater(
        adapter.listen(answerOk, address: loopback, port: 0),
        throwsStateError,
      );
    });

    test('close before listen completes and blocks a later listen', () async {
      final adapter = ShelfAdapter();

      await adapter.close();

      await expectLater(
        adapter.listen(answerOk, address: loopback, port: 0),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('close is idempotent and forgets the port', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(answerOk, address: loopback, port: 0);

      expect(identical(adapter.close(), adapter.close()), isTrue);
      await adapter.close();
      expect(() => adapter.port, throwsStateError);
    });

    test('a second concurrent listen throws and leaks no server', () async {
      final adapter = ShelfAdapter();
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
      final adapter = ShelfAdapter();

      final listening = adapter.listen(answerOk, address: loopback, port: port);
      final listenResult = expectLater(listening, throwsStateError);
      await adapter.close();

      await listenResult;
      await expectPortFree(port);
    });

    test('close(force: true) escalates a pending graceful close', () async {
      final release = Completer<void>();
      final entered = Completer<void>();
      addTearDown(() => release.isCompleted ? null : release.complete());
      final adapter = ShelfAdapter(closeTimeout: null);
      await adapter.listen(
        (request) async {
          entered.complete();
          await release.future;
          return HttpResponse.text('late');
        },
        address: loopback,
        port: 0,
      );
      final client = io.HttpClient();
      addTearDown(() => client.close(force: true));
      final pending = getRoot(client, adapter.port);
      unawaited(pending.then((_) {}, onError: (Object _) {}));
      await entered.future;
      final graceful = adapter.close();

      await adapter.close(force: true).timeout(const Duration(seconds: 5));

      await graceful.timeout(const Duration(seconds: 5));
    });
  });
}
