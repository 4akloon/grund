/// A provider for an already built constant [value], keyed by its static
/// type or by [token].
///
/// ```dart
/// const dbUrl = Token<String>('db.url');
///
/// @Module(providers: [Value('postgres://localhost/app', token: dbUrl)])
/// class DatabaseModule {}
/// ```
final class Value {
  /// Creates the provider.
  const Value(this.value, {this.token});

  /// The provided constant.
  final Object value;

  /// The `Token` to provide [value] under; `null` keys it by its type.
  final Object? token;
}
