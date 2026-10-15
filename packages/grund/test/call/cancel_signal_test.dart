import 'dart:async';

import 'package:grund/src/call/cancel_signal.dart';
import 'package:test/test.dart';

void main() {
  group('CancelSignal', () {
    test('is not cancelled at first', () {
      expect(CancelSignal().isCancelled, isFalse);
    });

    test('cancel completes whenCancelled and flips isCancelled', () async {
      final signal = CancelSignal();
      var notified = false;
      unawaited(signal.whenCancelled.then((_) => notified = true));

      signal.cancel();
      await signal.whenCancelled;

      expect(signal.isCancelled, isTrue);
      expect(notified, isTrue);
    });

    test('a second cancel does nothing', () async {
      final signal = CancelSignal()
        ..cancel()
        ..cancel();

      await signal.whenCancelled;

      expect(signal.isCancelled, isTrue);
    });
  });
}
