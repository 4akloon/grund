import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The keys typed in the terminal, for the `r` and `R` of `dev`.
abstract final class TerminalKeys {
  // The modes stdin had before [read] changed them; null while unchanged.
  static ({bool echo, bool line})? _previous;

  /// Whether stdin is a terminal, so that [read] gives keys.
  static bool get isInteractive => stdin.hasTerminal;

  /// Every key typed on stdin when it is a terminal; an empty stream
  /// otherwise. While the stream is listened to, stdin reads key by key
  /// without echo (Ctrl+C still interrupts); cancelling restores it.
  static Stream<String> read({Stdin? input}) {
    final terminal = input ?? stdin;
    if (!terminal.hasTerminal) return const Stream<String>.empty();
    StreamSubscription<String>? subscription;
    final controller = StreamController<String>();
    controller
      ..onListen = () {
        try {
          _previous = (echo: terminal.echoMode, line: terminal.lineMode);
          terminal
            ..echoMode = false
            ..lineMode = false;
        } on StdinException {
          // A stdin that claims to be a terminal but refuses its modes (a
          // redirected or closed one): no keys, `dev` still runs.
          unawaited(controller.close());
          return;
        }
        subscription = terminal
            .transform(const Utf8Decoder(allowMalformed: true))
            .expand((chunk) => chunk.split(''))
            .listen(controller.add);
      }
      ..onCancel = () async {
        await subscription?.cancel();
        restore(terminal);
      };
    return controller.stream;
  }

  /// Gives stdin the modes it had before [read], at once; does nothing
  /// when [read] did not change them or they are restored already. For the
  /// forced exit, which cannot wait for the stream's cancellation.
  static void restore([Stdin? input]) {
    final terminal = input ?? stdin;
    final previous = _previous;
    if (previous == null) return;
    _previous = null;
    try {
      // Line mode first: Windows refuses echo on while line mode is off.
      terminal
        ..lineMode = previous.line
        ..echoMode = previous.echo;
    } on StdinException {
      // The terminal went away (hang-up): nothing left to restore.
      return;
    }
  }
}
