import 'package:grund/grund.dart';

/// A failure of `grund_auth`: a cookie that cannot be written, or a session
/// configuration a browser would not honour.
sealed class AuthError extends GrundError {
  /// Creates the error.
  const AuthError(this.reason);

  /// What is wrong and what to do.
  final String reason;
}

/// A `SetCookie` with a name, value or path that would break the
/// `set-cookie` header (RFC 6265), or with attributes a browser drops.
final class CookieFormatError extends AuthError {
  /// Creates the error; [reason] says what is wrong.
  const CookieFormatError(super.reason);

  @override
  String get message => 'Invalid cookie: $reason';
}

/// A `SessionConfig` that cannot work; thrown when `SessionModule` starts,
/// before the server serves.
final class SessionConfigError extends AuthError {
  /// Creates the error; [reason] says what is wrong.
  const SessionConfigError(super.reason);

  @override
  String get message => 'Invalid SessionConfig: $reason';
}
