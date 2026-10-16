import 'dart:convert';

import '../auth_error.dart';
import '../cookie/cookie_attributes.dart';
import '../cookie/cookie_syntax.dart';
import '../cookie/same_site_policy.dart';

/// The session cookie and the same-origin check of `SessionModule`.
///
/// The cookie is always `HttpOnly` with `Path=/` and no `Domain`; its
/// lifetime is absolute ([maxAge] from the sign-in, not extended by use).
final class SessionConfig {
  /// Creates the configuration; [validate] checks it when `SessionModule`
  /// starts.
  const SessionConfig({
    this.cookieName = 'grund_sid',
    this.secure = true,
    this.maxAge = const Duration(days: 7),
    this.sameSite = SameSitePolicy.lax,
    this.sameOrigin = true,
  });

  /// The name of the session cookie.
  final String cookieName;

  /// Whether the cookie is `Secure` (sent over HTTPS only). Turn it off
  /// only for development over plain `http`.
  final bool secure;

  /// How long a session lasts, from the sign-in; at least one second.
  final Duration maxAge;

  /// The `SameSite` attribute of the cookie.
  final SameSitePolicy sameSite;

  /// Whether `SessionHook` refuses unsafe cross-site requests, as
  /// `SameOriginHook` does.
  final bool sameOrigin;

  /// The attributes of the session cookie, with [maxAge] as `Max-Age`.
  CookieAttributes attributes({required Duration maxAge}) =>
      CookieAttributes(maxAge: maxAge, secure: secure, sameSite: sameSite);

  /// Throws [SessionConfigError] when a browser would not keep the cookie
  /// or the header could not carry it.
  void validate() {
    final problem = _problem();
    if (problem != null) throw SessionConfigError(problem);
  }

  String? _problem() {
    if (!CookieSyntax.isName(cookieName)) {
      return 'cookieName ${jsonEncode(cookieName)} is not a cookie name.';
    }
    if (maxAge.inSeconds < 1) {
      return 'maxAge must be at least one second; it is $maxAge.';
    }
    if (sameSite == SameSitePolicy.none && !secure) {
      return 'SameSite=None needs secure: true; browsers drop the cookie.';
    }
    final prefixed = cookieName.toLowerCase();
    if (!secure &&
        (prefixed.startsWith('__host-') || prefixed.startsWith('__secure-'))) {
      return 'the prefix of $cookieName needs secure: true.';
    }
    return null;
  }
}
