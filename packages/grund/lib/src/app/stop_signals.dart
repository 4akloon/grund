import 'dart:async';
import 'dart:io';

/// Completes when the process is asked to stop.
final class StopSignals {
  /// Listens to the given [sources]; by default `SIGINT` and, where the
  /// platform has it, `SIGTERM`.
  StopSignals({Iterable<Stream<Object?>>? sources})
    : _sources = List.of(sources ?? _processSignals());

  final List<Stream<Object?>> _sources;

  /// Completes at the first event of any source and stops listening.
  Future<void> wait() {
    final completer = Completer<void>();
    final subscriptions = <StreamSubscription<Object?>>[];
    for (final source in _sources) {
      subscriptions.add(
        source.listen((_) {
          if (!completer.isCompleted) completer.complete();
        }),
      );
    }
    return completer.future.whenComplete(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
  }

  static List<Stream<Object?>> _processSignals() => [
    ProcessSignal.sigint.watch(),
    if (!Platform.isWindows) ProcessSignal.sigterm.watch(),
  ];
}
