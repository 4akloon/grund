import 'dart:io';

import 'package:grund_cli/src/dev/terminal_keys.dart';
import 'package:test/test.dart';

/// A stdin that claims to be a terminal and refuses its modes, like a
/// redirected one.
final class _RefusingStdin implements Stdin {
  @override
  bool get hasTerminal => true;

  @override
  bool get echoMode => throw const StdinException('no modes');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a stdin that refuses its modes gives no keys, not a crash', () async {
    final keys = TerminalKeys.read(input: _RefusingStdin());

    expect(await keys.toList(), isEmpty);
  });
}
