import 'dart:convert';

import '../auth_error.dart';
import 'cookie_attributes.dart';
import 'cookie_syntax.dart';
import 'same_site_policy.dart';

/// One `set-cookie` header value, checked when it is created.
///
/// ```dart
/// c.response.headers.add('set-cookie', SetCookie('theme', 'dark').toHeader());
/// ```
///
/// The attributes are written in a fixed order: `Max-Age`, `Path`,
/// `Secure`, `HttpOnly`, `SameSite`.
final class SetCookie {
  /// The cookie [name] with [value]; throws [CookieFormatError] for a name
  /// that is not a token, a value with characters outside the cookie
  /// octets, a path that is empty, does not start with `/` or has `;` or
  /// control characters, a negative `maxAge`, a positive `maxAge` shorter
  /// than one second (it would be written as `Max-Age=0` and delete the
  /// cookie), or `SameSite=None` without `Secure`.
  SetCookie(
    this.name,
    this.value, {
    this.attributes = const CookieAttributes(),
  }) {
    if (!CookieSyntax.isName(name)) {
      throw CookieFormatError('the name ${jsonEncode(name)} is not a token.');
    }
    if (!CookieSyntax.isValue(value)) {
      throw CookieFormatError(
        'the value of $name has a character a cookie cannot carry.',
      );
    }
    _checkAttributes();
  }

  /// The cookie name.
  final String name;

  /// The cookie value.
  final String value;

  /// `Max-Age`, `Path`, `Secure`, `HttpOnly` and `SameSite`.
  final CookieAttributes attributes;

  /// The header value: `name=value; Max-Age=...; Path=/; ...`.
  String toHeader() => [
    '$name=$value',
    if (attributes.maxAge case final maxAge?) 'Max-Age=${maxAge.inSeconds}',
    'Path=${attributes.path}',
    if (attributes.secure) 'Secure',
    if (attributes.httpOnly) 'HttpOnly',
    'SameSite=${attributes.sameSite.attribute}',
  ].join('; ');

  void _checkAttributes() {
    final path = attributes.path;
    if (!path.startsWith('/') || !CookieSyntax.isAttributeValue(path)) {
      throw CookieFormatError(
        'the path of $name must start with "/" and have no ";" or control '
        'character.',
      );
    }
    if (attributes.maxAge case final maxAge? when maxAge.isNegative) {
      throw CookieFormatError('the maxAge of $name is negative.');
    }
    if (attributes.maxAge case final maxAge?
        when maxAge > Duration.zero && maxAge < const Duration(seconds: 1)) {
      throw CookieFormatError(
        'the maxAge of $name is under one second; it would delete the cookie.',
      );
    }
    if (attributes.sameSite == SameSitePolicy.none && !attributes.secure) {
      throw CookieFormatError(
        '$name has SameSite=None without Secure; browsers drop it.',
      );
    }
  }
}
