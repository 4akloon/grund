import 'dart:async';

import 'package:watcher/watcher.dart';

/// A [Watcher] whose events the test sends.
final class FakeWatcher implements Watcher {
  /// Creates the watcher of directory [path].
  FakeWatcher(this.path, {bool ready = true}) {
    if (ready) becomeReady();
  }

  final _events = StreamController<WatchEvent>.broadcast();

  @override
  final String path;

  @override
  Stream<WatchEvent> get events => _events.stream;

  final _ready = Completer<void>();

  @override
  bool get isReady => _ready.isCompleted;

  @override
  Future<void> get ready => _ready.future;

  /// Whether anything listens to [events].
  bool get hasListener => _events.hasListener;

  /// Makes [ready] complete.
  void becomeReady() => _ready.complete();

  /// Reports [error] on [events].
  void error(Object error) => _events.addError(error);

  /// Reports that [file] was modified.
  void modify(String file) => _events.add(WatchEvent(ChangeType.MODIFY, file));
}
