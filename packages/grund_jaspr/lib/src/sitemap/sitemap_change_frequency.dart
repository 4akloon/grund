/// How often a page changes, as the sitemap protocol names it.
enum SitemapChangeFrequency {
  /// Changes on every access.
  always,

  /// Changes hourly.
  hourly,

  /// Changes daily.
  daily,

  /// Changes weekly.
  weekly,

  /// Changes monthly.
  monthly,

  /// Changes yearly.
  yearly,

  /// Never changes (archived).
  never,
}
