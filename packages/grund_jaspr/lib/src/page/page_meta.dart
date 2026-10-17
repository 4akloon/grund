import 'page_nav.dart';
import 'page_sitemap.dart';

/// What the framework knows about a page besides how to render it.
final class PageMeta {
  /// Creates the metadata.
  const PageMeta({
    this.title = '',
    this.description,
    this.nav,
    this.sitemap = const PageSitemap(),
  });

  /// The page title.
  final String title;

  /// A short description of the page.
  final String? description;

  /// The navigation entry; the page is not in the navigation when `null`.
  final PageNav? nav;

  /// The sitemap settings.
  final PageSitemap sitemap;
}
