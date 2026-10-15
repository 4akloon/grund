/// Resolves a constructor parameter by a `Token` instead of its type.
///
/// ```dart
/// const dbUrl = Token<String>('db.url');
///
/// @Injectable()
/// class Db {
///   Db(@Inject(dbUrl) this.url);
///   final String url;
/// }
/// ```
final class Inject {
  /// Creates the annotation for [token], a `Token` constant.
  const Inject(this.token);

  /// The `Token` to resolve.
  final Object token;
}
