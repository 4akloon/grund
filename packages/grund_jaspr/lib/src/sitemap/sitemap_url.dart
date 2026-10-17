import 'sitemap_change_frequency.dart';

/// One address of a sitemap.
final class SitemapUrl {
  /// Creates the address [location].
  const SitemapUrl({
    required this.location,
    this.lastModified,
    this.changeFrequency,
    this.priority,
  });

  /// The absolute URL.
  final Uri location;

  /// When the page last changed.
  final DateTime? lastModified;

  /// How often the page changes.
  final SitemapChangeFrequency? changeFrequency;

  /// The priority from 0.0 to 1.0.
  final double? priority;
}
