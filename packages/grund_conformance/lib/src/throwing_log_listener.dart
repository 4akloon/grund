import 'dart:async';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// A listener of `Logger.root.onRecord` that throws on every record, to prove
/// that a failing log listener (user code) does not change the responses.
///
/// The framework does not contain the failure: `package:logging` delivers
/// records through a stream, so a listener's exception goes to the zone the
/// listener was registered in (an uncaught asynchronous error in a plain
/// `main`). Here a guarded zone collects it in [failures] instead of failing
/// the test.
final class ThrowingLogListener {
  ThrowingLogListener._();

  /// Attaches the listener; the tear-down of the current test detaches it.
  factory ThrowingLogListener.attach() {
    final listener = ThrowingLogListener._();
    runZonedGuarded(() {
      final subscription = Logger.root.onRecord.listen(
        (_) => throw StateError('log listener failed'),
      );
      addTearDown(subscription.cancel);
    }, (error, _) => listener.failures.add(error));
    return listener;
  }

  /// What the listener threw, oldest first.
  final List<Object> failures = [];
}
