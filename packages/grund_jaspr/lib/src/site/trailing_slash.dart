/// How a site spells the end of its page URLs.
enum TrailingSlash {
  /// Both spellings are served as they are; links and the sitemap use the
  /// declared path, without a slash.
  ignore,

  /// No slash at the end; `/about/` redirects to `/about` (308).
  never,

  /// A slash at the end of every page URL except one whose last segment has
  /// an extension; `/about` redirects to `/about/` (308).
  always,
}
