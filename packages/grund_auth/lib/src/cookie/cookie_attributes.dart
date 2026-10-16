import 'same_site_policy.dart';

/// The attributes of a `SetCookie`; the defaults suit a session cookie.
///
/// There is no `Domain` (the cookie stays with the host that set it) and
/// no `Expires` (`Max-Age` says the same to every current browser).
final class CookieAttributes {
  /// Creates the attributes.
  const CookieAttributes({
    this.maxAge,
    this.path = '/',
    this.secure = true,
    this.httpOnly = true,
    this.sameSite = SameSitePolicy.lax,
  });

  /// How long the browser keeps the cookie, in whole seconds; `null` keeps
  /// it until the browser closes, [Duration.zero] deletes it.
  final Duration? maxAge;

  /// The path prefix the browser sends the cookie for.
  final String path;

  /// Whether the browser sends the cookie over HTTPS only.
  final bool secure;

  /// Whether scripts of the page cannot read the cookie.
  final bool httpOnly;

  /// When the browser sends the cookie with a request another site started.
  final SameSitePolicy sameSite;
}
