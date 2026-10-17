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

/// Holds the current [PageSnapshot]; replaced when the runner reassembles.
final class PageRegistry {
  /// Creates an empty registry.
  PageRegistry();

  /// The latest snapshot; `null` until the runner has built one.
  PageSnapshot? current;

  /// Makes [snapshot] the current one.
  void replace(PageSnapshot snapshot) => current = snapshot;
}
