import 'dart:async';

import 'package:watcher/watcher.dart';

/// One [Watcher] over the directories of several watchers: `dev` watches
/// `lib/` and the directory of its entry point.
final class MergedWatcher implements Watcher {
  /// Merges [watchers]; [path] is the directory they belong to (the
  /// package root).
  MergedWatcher(this.path, this.watchers);

  @override
  final String path;

  /// The merged watchers.
  final List<Watcher> watchers;

  /// The events of every watcher. Each read gives a new single-subscription
  /// stream; listening to it starts the watchers, cancelling it stops them.
  @override
  Stream<WatchEvent> get events {
    final subscriptions = <StreamSubscription<WatchEvent>>[];
    final controller = StreamController<WatchEvent>();
    controller
      ..onListen = () {
        for (final watcher in watchers) {
          subscriptions.add(
            watcher.events.listen(controller.add, onError: controller.addError),
          );
        }
      }
      ..onCancel = () => Future.wait([
        for (final subscription in subscriptions) subscription.cancel(),
      ]);
    return controller.stream;
  }

  @override
  bool get isReady => watchers.every((watcher) => watcher.isReady);

  @override
  Future<void> get ready =>
      Future.wait([for (final watcher in watchers) watcher.ready]);
}
