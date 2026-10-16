/// The `SameSite` attribute of a cookie: when a browser sends it with a
/// request that another site started.
enum SameSitePolicy {
  /// Sent with top-level navigations from other sites, not with their
  /// subrequests or form posts.
  lax('Lax'),

  /// Never sent with a request another site started.
  strict('Strict'),

  /// Always sent; browsers require `Secure` with it.
  none('None');

  const SameSitePolicy(this.attribute);

  /// The value written after `SameSite=`.
  final String attribute;
}
