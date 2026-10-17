import 'pages_api.dart';
import 'page_site.dart';
import 'site_api.dart';

/// What the pages runner found in the module graph: every site and every
/// pages declaration.
final class PageSnapshot {
  /// Creates the snapshot.
  const PageSnapshot({required this.sites, required this.pages});

  /// The site routes of every declared site.
  final List<SiteApi<PageSite>> sites;

  /// The page routes of every `Pages.under`.
  final List<PagesApi<PageSite>> pages;
}
