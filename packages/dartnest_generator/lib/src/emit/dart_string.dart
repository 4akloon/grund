/// Writes user strings (ids, paths, names) as Dart string literals.
///
/// `code_builder`'s `literalString` escapes only quotes and newlines; a
/// user string reaches generated code only through [literal], which also
/// escapes `\`, `$`, every control character (C0, DEL and C1), the line and
/// paragraph separators and lone surrogates.
abstract final class DartString {
  /// [value] as a single-quoted Dart literal.
  static String literal(String value) {
    return "'${escape(value)}'";
  }

  /// [value] escaped for the inside of a single-quoted literal, without the
  /// quotes: the form for a URI in a directive.
  static String escape(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      buffer.write(_escape(rune));
    }
    return '$buffer';
  }

  static String _escape(int rune) => switch (rune) {
    0x5C => r'\\',
    0x27 => r"\'",
    0x24 => r'\$',
    0x0A => r'\n',
    0x0D => r'\r',
    0x09 => r'\t',
    < 0x20 ||
    0x7F ||
    >= 0x80 && <= 0x9F ||
    0x2028 ||
    0x2029 ||
    >= 0xD800 && <= 0xDFFF => '\\u{${rune.toRadixString(16)}}',
    _ => String.fromCharCode(rune),
  };
}
