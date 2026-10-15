import 'dart:async';

import 'package:grund/adapter.dart';
import 'package:test/test.dart';

void main() {
  group('InFlightRequests', () {
    test('is idle at once when nothing is tracked', () async {
      final requests = InFlightRequests();

      await requests.idle;

      expect(requests.count, 0);
    });

    test('becomes idle when the last tracked operation ends', () async {
      final requests = InFlightRequests();
      final gate = Completer<void>();
      final tracked = requests.track(() => gate.future);
      var idle = false;
      unawaited(requests.idle.then((_) => idle = true));

      await Future<void>.delayed(Duration.zero);
      expect((requests.count, idle), (1, false));

      gate.complete();
      await tracked;
      await requests.idle;
      expect((requests.count, idle), (0, true));
    });

    test('stops counting an operation that fails', () async {
      final requests = InFlightRequests();

      await expectLater(
        requests.track<void>(() async => throw StateError('failed')),
        throwsStateError,
      );

      expect(requests.count, 0);
      await requests.idle;
    });
  });
}
