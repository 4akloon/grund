import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The keys typed in the terminal, for the `r` and `R` of `dev`.
abstract final class TerminalKeys {
  /// Every key typed on stdin when it is a terminal; an empty stream
  /// otherwise. While the stream is listened to, stdin reads key by key
  /// without echo (Ctrl+C still interrupts); cancelling restores it.
  static Stream<String> read() {
    if (!stdin.hasTerminal) return const Stream<String>.empty();
    StreamSubscription<String>? subscription;
    final controller = StreamController<String>();
    controller
      ..onListen = () {
        stdin
          ..echoMode = false
          ..lineMode = false;
        subscription = stdin
            .transform(const Utf8Decoder(allowMalformed: true))
            .expand((chunk) => chunk.split(''))
            .listen(controller.add);
      }
      ..onCancel = () async {
        await subscription?.cancel();
        stdin
          ..lineMode = true
          ..echoMode = true;
      };
    return controller.stream;
  }
}
