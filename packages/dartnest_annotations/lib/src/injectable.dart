/// Marks a class that dependency injection creates through its unnamed
/// constructor; list it in `Module.providers`.
///
/// Every constructor parameter is resolved by its type, or by the token of
/// its `Inject` annotation. Named parameters must be `required`.
///
/// ```dart
/// @Injectable()
/// class UsersService {
///   UsersService(this.repo, @Inject(dbUrl) this.url);
///   final UsersRepo repo;
///   final String url;
/// }
/// ```
final class Injectable {
  /// Creates the annotation.
  const Injectable();
}
