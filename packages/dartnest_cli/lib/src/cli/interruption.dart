import 'dart:async';
import 'dart:io';

/// How a command line is stopped: by the first interrupt, and, when
/// stopping hangs, by the second.
///
/// Tests replace its parts; by default they are the process's interrupt
/// signals and `exit`.
final class Interruption {
  /// Creates the interruption. [signals] are the interrupt signals (the
  /// system's by default); [untilStopped] completes on the first of them,
  /// or on [signals]' first event when not given; [forceExit] ends the
  /// process at once (`exit` by default).
  Interruption({
    Future<void> Function()? untilStopped,
    Stream<void> Function()? signals,
    void Function(int code)? forceExit,
  }) : signals = signals ?? system,
       forceExit = forceExit ?? exit,
       untilStopped = untilStopped ?? (() => (signals ?? system)().first);

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

  /// Completes on the first interrupt; `gen --watch` and `dev` stop then.
  final Future<void> Function() untilStopped;

  /// Every interrupt received while it is listened to; `dev` listens for
  /// the ones that come while it is shutting down.
  final Stream<void> Function() signals;

  /// Ends the process with an exit code at once, without cleaning up.
  final void Function(int code) forceExit;
}
