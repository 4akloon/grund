/// Writes user strings (ids, paths, names) as Dart string literals.
///
/// `code_builder`'s `literalString` escapes only quotes and newlines; a
/// user string reaches generated code only through [literal], which also
/// escapes `\`, `$` and every control character.
abstract final class DartString {
  /// [value] as a single-quoted Dart literal.
  static String literal(String value) {
    final buffer = StringBuffer("'");
    for (final rune in value.runes) {
      buffer.write(_escape(rune));
    }
    buffer.write("'");
    return '$buffer';
  }

  static String _escape(int rune) => switch (rune) {
    0x5C => r'\\',
    0x27 => r"\'",
    0x24 => r'\$',
    0x0A => r'\n',
    0x0D => r'\r',
    0x09 => r'\t',
    < 0x20 || 0x7F || 0x2028 || 0x2029 => '\\u{${rune.toRadixString(16)}}',
    _ => String.fromCharCode(rune),
  };
}
