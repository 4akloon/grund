import 'dart:async';

import 'package:dartnest_cli/src/dev/merged_watcher.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import 'helpers/fake_watcher.dart';

void main() {
  test('delivers the events of every watcher', () async {
    final lib = FakeWatcher('/pkg/lib');
    final bin = FakeWatcher('/pkg/bin');
    final merged = MergedWatcher('/pkg', [lib, bin]);
    final events = <String>[];
    final subscription = merged.events.listen(
      (event) => events.add(event.path),
    );
    await merged.ready;

    lib.modify('/pkg/lib/a.dart');
    bin.modify('/pkg/bin/main.dart');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(events, ['/pkg/lib/a.dart', '/pkg/bin/main.dart']);
    expect(merged.isReady, isTrue);
  });

  test('cancelling stops listening to every watcher', () async {
    final lib = FakeWatcher('/pkg/lib');
    final entry = FakeWatcher('/pkg/bin');
    final merged = MergedWatcher('/pkg', <Watcher>[lib, entry]);
    final events = <WatchEvent>[];
    final subscription = merged.events.listen(events.add);
    expect(lib.hasListener && entry.hasListener, isTrue);

    await subscription.cancel();

    expect(lib.hasListener, isFalse);
    expect(entry.hasListener, isFalse);
  });

  test('ready completes only after every watcher is ready', () async {
    final lib = FakeWatcher('/pkg/lib', ready: false);
    final entry = FakeWatcher('/pkg/bin', ready: false);
    final merged = MergedWatcher('/pkg', [lib, entry]);
    var ready = false;
    unawaited(merged.ready.then((_) => ready = true));

    lib.becomeReady();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ready, isFalse);
    expect(merged.isReady, isFalse);

    entry.becomeReady();
    await merged.ready;
    expect(merged.isReady, isTrue);
  });

  test('errors of either watcher are forwarded', () async {
    final lib = FakeWatcher('/pkg/lib');
    final entry = FakeWatcher('/pkg/bin');
    final merged = MergedWatcher('/pkg', [lib, entry]);
    final errors = <Object>[];
    final subscription = merged.events.listen((_) {}, onError: errors.add);

    lib.error('a');
    entry.error('b');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(errors, ['a', 'b']);
  });
}
