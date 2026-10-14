import 'dart:async';

import 'package:watcher/watcher.dart';

/// A [Watcher] whose events the test sends.
final class FakeWatcher implements Watcher {
  /// Creates the watcher of directory [path].
  FakeWatcher(this.path);

  final _events = StreamController<WatchEvent>.broadcast();

  @override
  final String path;

  @override
  Stream<WatchEvent> get events => _events.stream;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready => Future.value();

  /// Reports that [file] was modified.
  void modify(String file) => _events.add(WatchEvent(ChangeType.MODIFY, file));
}
