import 'dart:async';

import '../errors/resolution_errors.dart';

/// Runs steps that must all be tried even when some fail, and remembers the
/// failures.
final class ShutdownSteps {
  final List<ShutdownFailure> _failures = [];

  /// The steps that failed so far, in order.
  List<ShutdownFailure> get failures => List.unmodifiable(_failures);

  /// Runs [action], recording its failure as [step].
  Future<void> run(String step, FutureOr<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      // Boundary: dispose and onShutdown are user code; a failure must not
      // stop the steps after it.
      _failures.add((step: step, error: error, stackTrace: stackTrace));
    }
  }

  /// Throws a [ShutdownError] with all failures, if there are any.
  void throwIfFailed() {
    if (_failures.isNotEmpty) throw ShutdownError(failures);
  }
}
