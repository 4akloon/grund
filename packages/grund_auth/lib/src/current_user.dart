/// The signed-in user of a request, in its call scope.
///
/// `SessionHook` sets it for a request with a live session; read it with
/// `c.maybe<CurrentUser>()` in a handler or hook, and with
/// `context.maybe<CurrentUser>()` in a `grund_jaspr` page.
final class CurrentUser {
  /// The user [id], with optional [claims].
  const CurrentUser(this.id, {this.claims = const {}});

  /// The id the application passed to `Sessions.start`.
  final String id;

  /// What else the application knows about the user; empty for a user of a
  /// session.
  final Map<String, Object?> claims;

  @override
  String toString() => 'CurrentUser($id)';
}
