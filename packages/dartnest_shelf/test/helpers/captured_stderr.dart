import 'dart:async';
import 'dart:io' as io;

/// A `Stdout` that records what is written with `writeln`.
final class _CapturingStdout implements io.Stdout {
  final StringBuffer lines = StringBuffer();

  @override
  void writeln([Object? object = '']) => lines.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Runs [body] with `dart:io`'s `stderr` captured (for code that starts
/// inside [body], including servers it binds) and returns what was written.
Future<String> captureStderr(Future<void> Function() body) async {
  final captured = _CapturingStdout();
  await io.IOOverrides.runZoned(body, stderr: () => captured);
  return captured.lines.toString();
}
