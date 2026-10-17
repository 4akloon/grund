import '../sitemap/sitemap_change_frequency.dart';
import '../sitemap/sitemap_entries.dart';

/// How a page appears in the sitemap.
final class PageSitemap {
  /// Creates the sitemap settings.
  const PageSitemap({
    this.included,
    this.lastModified,
    this.changeFrequency,
    this.priority,
    this.entries,
  });

  /// Whether the page is listed. `null` lets the rules decide: a page that
  /// has its own `hooks.use` stays out of the sitemap and navigation unless
  /// this is `true`; `false` always leaves it out.
  final bool? included;

  /// When the page last changed.
  final DateTime? lastModified;

  /// How often the page changes.
  final SitemapChangeFrequency? changeFrequency;

  /// The priority from 0.0 to 1.0.
  final double? priority;

  /// The addresses of a parameterised page.
  final SitemapEntries? entries;
}
