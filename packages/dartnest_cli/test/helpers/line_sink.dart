import 'dart:async';

/// A [StringSink] that records complete lines and lets a test wait for the
/// next one.
final class LineSink implements StringSink {
  final _lines = <String>[];
  final _partial = StringBuffer();
  var _read = 0;
  Completer<void>? _arrived;

  /// Every complete line so far.
  List<String> get lines => List.unmodifiable(_lines);

  /// The next line not returned before, waiting up to [timeout] for it.
  Future<String> next({Duration timeout = const Duration(seconds: 30)}) async {
    while (_read == _lines.length) {
      await (_arrived ??= Completer<void>()).future.timeout(timeout);
    }
    return _lines[_read++];
  }

  /// The next line not returned before that satisfies [test], skipping
  /// the lines before it, waiting up to [timeout] in all.
  Future<String> nextWhere(
    bool Function(String line) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      final line = await next(timeout: timeout - stopwatch.elapsed);
      if (test(line)) return line;
    }
  }

  /// Waits [quiet] and returns the lines that arrived meanwhile.
  Future<List<String>> after(Duration quiet) async {
    final start = _lines.length;
    await Future<void>.delayed(quiet);
    _read = _lines.length;
    return _lines.sublist(start);
  }

  @override
  void write(Object? object) {
    _partial.write(object);
    final text = '$_partial';
    final end = text.lastIndexOf('\n');
    if (end < 0) return;
    _partial
      ..clear()
      ..write(text.substring(end + 1));
    _lines.addAll(text.substring(0, end).split('\n'));
    _arrived?.complete();
    _arrived = null;
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
}
