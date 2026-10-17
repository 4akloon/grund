/// One concrete address of a parameterised page in the sitemap.
final class SitemapEntry {
  /// Creates an entry for the path parameters [params].
  const SitemapEntry({required this.params, this.lastModified});

  /// The value of every path parameter of the page.
  final Map<String, String> params;

  /// When this address last changed.
  final DateTime? lastModified;
}
