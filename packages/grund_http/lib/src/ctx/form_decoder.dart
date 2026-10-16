/// Decodes an `application/x-www-form-urlencoded` body (what a browser
/// sends for a `<form method="post">`).
///
/// Fields are separated by `&`, a name from its value by the first `=`; `+`
/// is a space and `%XX` a byte of UTF-8. A field without `=` has the value
/// `''`; empty fields (`a=1&&b=2`) are skipped.
abstract final class FormDecoder {
  static final _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  /// The values of every field of [text], by name, in order; throws a
  /// [FormatException] for a `%` that is not followed by two hex digits or
  /// escapes that are not UTF-8.
  static Map<String, List<String>> decode(String text) {
    final fields = <String, List<String>>{};
    for (final field in text.split('&')) {
      if (field.isEmpty) continue;
      final split = field.indexOf('=');
      final name = _component(split < 0 ? field : field.substring(0, split));
      final value = split < 0 ? '' : _component(field.substring(split + 1));
      (fields[name] ??= []).add(value);
    }
    return fields;
  }

  static String _component(String raw) {
    if (_badEscape.hasMatch(raw)) {
      throw const FormatException('A "%" is not followed by two hex digits.');
    }
    return Uri.decodeQueryComponent(raw);
  }
}
