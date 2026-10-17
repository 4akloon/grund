import '../page/site_page.dart';
import '../site/page_snapshot.dart';

/// The pages of a [PageSnapshot] as [SitePage]s.
abstract final class SnapshotPages {
  /// Every page of every site, sorted by path.
  static List<SitePage> all(PageSnapshot snapshot) => [
    for (final api in snapshot.pages)
      for (final page in api.pages)
        SitePage(site: api.site, page: page, path: api.fullPathOf(page)),
  ]..sort((a, b) => a.path.compareTo(b.path));
}
