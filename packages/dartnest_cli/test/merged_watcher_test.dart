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
    final merged = MergedWatcher('/pkg', <Watcher>[lib]);
    final events = <WatchEvent>[];
    final subscription = merged.events.listen(events.add);

    await subscription.cancel();
    lib.modify('/pkg/lib/a.dart');
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
  });
}
