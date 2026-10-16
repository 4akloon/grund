/// The characters RFC 6265 allows in a cookie name, value and attribute.
abstract final class CookieSyntax {
  static final _token = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final _value = RegExp(
    r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]*$',
  );
  static final _attribute = RegExp(r'^[\x20-\x3A\x3C-\x7E]*$');

  /// Whether [name] is a token: not empty, no separators, no spaces, no
  /// control characters.
  static bool isName(String name) => _token.hasMatch(name);

  /// Whether [value] has only cookie octets: no spaces, quotes, commas,
  /// semicolons, backslashes or control characters (empty is allowed).
  static bool isValue(String value) => _value.hasMatch(value);

  /// Whether [value] can follow an attribute name: no `;` and no control
  /// characters.
  static bool isAttributeValue(String value) => _attribute.hasMatch(value);
}
