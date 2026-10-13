import 'dart:async';
import 'dart:typed_data';

/// Deterministic payloads for body tests: byte `i` is `i % 251`, so a
/// shifted or lost chunk changes the checksum.
abstract final class ConformanceData {
  /// Size of the chunks [chunks] emits.
  static const chunkSize = 64 * 1024;

  /// The payload of [length] bytes.
  static Uint8List bytes(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) i % 251]);

  /// The payload of [length] bytes as a stream of [chunkSize] chunks.
  static Stream<List<int>> chunks(int length) async* {
    for (var start = 0; start < length; start += chunkSize) {
      final end = start + chunkSize < length ? start + chunkSize : length;
      yield Uint8List.fromList([for (var i = start; i < end; i++) i % 251]);
    }
  }

  /// Adler-style checksum of [bytes] (sum modulo 65521).
  static int checksum(Iterable<int> bytes) =>
      bytes.fold(0, (sum, byte) => (sum + byte) % 65521);

  /// A stream that emits 16 KiB chunks every millisecond until it is
  /// cancelled, then calls [onCancel]. A plain controller rather than an
  /// `async*` body: a generator cancelled before its first run never
  /// reaches its `finally`.
  static Stream<List<int>> endless(void Function() onCancel) {
    final chunk = Uint8List(16 * 1024);
    final controller = StreamController<List<int>>();
    Timer? timer;
    void start() => timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => controller.add(chunk),
    );
    void stop() => timer?.cancel();
    controller
      ..onListen = start
      ..onPause = stop
      ..onResume = start
      ..onCancel = () {
        stop();
        onCancel();
      };
    return controller.stream;
  }
}
