import 'dart:async';

import 'package:grund/src/di/disposable.dart';

/// A [Disposable] that writes to a log, optionally failing.
final class Tracked implements Disposable {
  Tracked(this.name, this.log, {this.failure});

  final String name;
  final List<String> log;
  final Object? failure;

  @override
  FutureOr<void> dispose() {
    log.add('dispose $name');
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}
