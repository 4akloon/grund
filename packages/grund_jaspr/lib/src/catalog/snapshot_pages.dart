import '../page/site_page.dart';
import '../site/page_snapshot.dart';

/// The pages of a [PageSnapshot] as [SitePage]s.
abstract final class SnapshotPages {
  /// Every page of every site, sorted by path.
  static List<SitePage> all(PageSnapshot snapshot) =>
      _sorted(_collect(snapshot, null));

  /// The pages of the site whose type is exactly [siteType], sorted by path.
  static List<SitePage> ofSite(PageSnapshot snapshot, Type siteType) =>
      _sorted(_collect(snapshot, siteType));

  static List<SitePage> _collect(PageSnapshot snapshot, Type? siteType) => [
    for (final api in snapshot.pages)
      if (siteType == null || api.siteType == siteType)
        for (final page in api.pages)
          SitePage(site: api.site, page: page, path: api.fullPathOf(page)),
  ];

  static List<SitePage> _sorted(List<SitePage> pages) =>
      pages..sort((a, b) => a.path.compareTo(b.path));
}
