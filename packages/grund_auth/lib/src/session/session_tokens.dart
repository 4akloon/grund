import 'dart:convert';
import 'dart:math';

/// Creates and recognises session tokens: 32 random bytes from a
/// cryptographically secure source, base64url without padding (43
/// characters).
final class SessionTokens {
  /// Draws from [random]; `Random.secure()` unless a test passes its own.
  SessionTokens([Random? random]) : _random = random ?? Random.secure();

  /// The number of random bytes of a token.
  static const byteCount = 32;

  static final _shape = RegExp(r'^[A-Za-z0-9_-]{43}$');

  final Random _random;

  /// A new token.
  String next() => base64Url
      .encode([for (var i = 0; i < byteCount; i++) _random.nextInt(256)])
      .replaceAll('=', '');

  /// Whether [token] has the shape of a token; anything else is not looked
  /// up in the store.
  static bool isWellFormed(String token) => _shape.hasMatch(token);
}
