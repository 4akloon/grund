import '../page/page.dart';
import 'pages_api.dart';
import 'page_site.dart';
import 'site_api.dart';

/// The pages one [PagesApi] declared when the snapshot was taken.
typedef DeclaredPages = ({PagesApi<PageSite> api, List<Page> pages});

/// What the pages runner found in the module graph: every site and every
/// pages declaration.
final class PageSnapshot {
  /// Creates the snapshot, reading the pages of every api in [pages] once.
  ///
  /// The declared pages are kept: an api adopted by a later reload runs the
  /// new declaration, which the snapshot must not index if it was rejected.
  PageSnapshot({required this.sites, required this.pages})
    : declared = [for (final api in pages) (api: api, pages: api.pages)];

  /// The site routes of every declared site.
  final List<SiteApi<PageSite>> sites;

  /// The page routes of every `Pages.under`.
  final List<PagesApi<PageSite>> pages;

  /// The pages of every api in [pages], as read when the snapshot was taken.
  final List<DeclaredPages> declared;
}
