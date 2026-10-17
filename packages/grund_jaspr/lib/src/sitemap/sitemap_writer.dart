import 'sitemap_url.dart';

/// Writes sitemap XML: a `urlset` of addresses or an index of files.
abstract final class SitemapWriter {
  static const _declaration = '<?xml version="1.0" encoding="UTF-8"?>';
  static const _namespace = 'http://www.sitemaps.org/schemas/sitemap/0.9';

  /// The `urlset` document of [urls].
  static String urlSet(Iterable<SitemapUrl> urls) {
    final buffer = StringBuffer(_declaration)
      ..write('<urlset xmlns="$_namespace">');
    for (final url in urls) {
      buffer.write('<url><loc>${_escape(url.location.toString())}</loc>');
      final lastModified = url.lastModified;
      if (lastModified != null) {
        buffer.write(
          '<lastmod>${lastModified.toUtc().toIso8601String()}</lastmod>',
        );
      }
      final changeFrequency = url.changeFrequency;
      if (changeFrequency != null) {
        buffer.write('<changefreq>${changeFrequency.name}</changefreq>');
      }
      final priority = url.priority;
      if (priority != null) {
        buffer.write('<priority>${priority.toStringAsFixed(1)}</priority>');
      }
      buffer.write('</url>');
    }
    return (buffer..write('</urlset>')).toString();
  }

  /// The `sitemapindex` document that lists the files [sitemaps].
  static String index(Iterable<Uri> sitemaps) {
    final buffer = StringBuffer(_declaration)
      ..write('<sitemapindex xmlns="$_namespace">');
    for (final sitemap in sitemaps) {
      buffer.write(
        '<sitemap><loc>${_escape(sitemap.toString())}</loc></sitemap>',
      );
    }
    return (buffer..write('</sitemapindex>')).toString();
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&apos;')
      .replaceAll('"', '&quot;');
}
