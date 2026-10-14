import 'dart:async';
import 'dart:io';

/// How a command line is stopped: by the first interrupt, and, when
/// stopping hangs, by the second.
///
/// Tests replace its parts; by default they are the process's interrupt
/// signals and `exit`. A command listens with [listen] and cancels the
/// subscription when it is done: a listener on the signals keeps the VM
/// alive.
final class Interruption {
  /// Creates the interruption. [signals] are the interrupt signals (the
  /// system's by default); [untilStopped], when given (tests), also stops
  /// the command when it completes; [forceExit] ends the process at once
  /// (`exit` by default).
  Interruption({
    this.untilStopped,
    Stream<void> Function()? signals,
    void Function(int code)? forceExit,
  }) : signals = signals ?? system,
       forceExit = forceExit ?? exit;

  /// An event per `SIGINT` (Ctrl+C) or, outside Windows, where it cannot be
  /// watched, `SIGTERM`, while the stream is listened to.
  static Stream<void> system() => Stream<void>.multi((controller) {
    final subscriptions = [
      for (final signal in [
        ProcessSignal.sigint,
        if (!Platform.isWindows) ProcessSignal.sigterm,
      ])
        signal.watch().listen((_) => controller.add(null)),
    ];
    controller.onCancel = () => Future.wait([
      for (final subscription in subscriptions) subscription.cancel(),
    ]);
  });

  /// Completes when a test asks the command to stop; `null` outside tests.
  final Future<void> Function()? untilStopped;

  /// Every interrupt received while it is listened to.
  final Stream<void> Function() signals;

  /// Ends the process with an exit code at once, without cleaning up.
  final void Function(int code) forceExit;

  /// Listens to [signals]: [stopped] completes on the first interrupt (or
  /// when [untilStopped] completes) and [onSignal] gets the number of every
  /// interrupt, the first included. The caller cancels [subscription] when
  /// its command ends, whatever way it ends.
  ({Future<void> stopped, StreamSubscription<void> subscription}) listen(
    void Function(int received) onSignal,
  ) {
    final stopped = Completer<void>();
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    unawaited(untilStopped?.call().then((_) => stop()));
    var received = 0;
    final subscription = signals().listen((_) {
      onSignal(++received);
      stop();
    });
    return (stopped: stopped.future, subscription: subscription);
  }
}
