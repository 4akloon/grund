import 'dart:async';

import 'package:grund_http/grund_http.dart';
import 'package:grund_shelf/src/shelf_bridge.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  group('ShelfBridge', () {
    final errors = <Object>[];

    setUp(errors.clear);

    shelf.Handler bridgeTo(HttpResponse response) => ShelfBridge(
      (_) async => response,
      onError: (error, _) => errors.add(error),
    ).call;

    // A function: a request body can be read only once.
    shelf.Request head() =>
        shelf.Request('HEAD', Uri.parse('http://localhost/'));

    test('HEAD cancels a stream body unread', () async {
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);

      final response = await bridgeTo(HttpResponse.stream(source.stream))(
        head(),
      );

      await cancelled.future;
      expect(response.statusCode, 200);
      expect(await response.readAsString(), isEmpty);
    });

    test(
      'HEAD reports a stream whose cancel throws and still answers',
      () async {
        final source = StreamController<List<int>>(
          onCancel: () => throw StateError('cancel failed'),
        );

        final response = await bridgeTo(HttpResponse.stream(source.stream))(
          head(),
        );

        expect(response.statusCode, 200);
        expect(errors, [isA<StateError>()]);
      },
    );

    test('HEAD reports a stream somebody already listens to', () async {
      final source = StreamController<List<int>>()..stream.listen(null);

      final response = await bridgeTo(HttpResponse.stream(source.stream))(
        head(),
      );

      expect(response.statusCode, 200);
      expect(errors, [isA<StateError>()]);
    });
  });
}
