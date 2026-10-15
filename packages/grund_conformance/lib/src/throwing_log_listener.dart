import 'dart:async';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// A listener of `Logger.root.onRecord` that throws on every record, to prove
/// that a failing log listener (user code) does not touch the responses.
///
/// `package:logging` delivers records synchronously but reports a listener's
/// exception to the zone the listener was registered in, so it is collected
/// in [failures] by a guarded zone instead of failing the test.
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
