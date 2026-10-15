/// Reads the `Cookie` request header.
abstract final class CookieHeader {
  /// The cookies of the header [values] by name; a name repeated keeps all
  /// its values, a double-quoted value loses the quotes. A pair without `=`
  /// is ignored.
  static Map<String, List<String>> parse(List<String> values) {
    final cookies = <String, List<String>>{};
    for (final header in values) {
      for (final pair in header.split(';')) {
        final separator = pair.indexOf('=');
        if (separator < 0) continue;
        final name = pair.substring(0, separator).trim();
        if (name.isEmpty) continue;
        cookies
            .putIfAbsent(name, () => [])
            .add(_unquote(pair.substring(separator + 1).trim()));
      }
    }
    return cookies;
  }

  static String _unquote(String value) =>
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
      ? value.substring(1, value.length - 1)
      : value;
}
