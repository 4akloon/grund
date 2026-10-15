import 'dart:async';

import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('StopSignals', () {
    test('completes at the first event of any source', () async {
      final first = StreamController<int>();
      final second = StreamController<int>();
      final signals = StopSignals(sources: [first.stream, second.stream]);
      var done = false;

      final waiting = signals.wait().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      second.add(1);
      await waiting;

      expect(done, isTrue);
    });

    test('stops listening once it completed', () async {
      final source = StreamController<int>();
      final waiting = StopSignals(sources: [source.stream]).wait();

      source.add(1);
      await waiting;

      expect(source.hasListener, isFalse);
    });
  });
}
