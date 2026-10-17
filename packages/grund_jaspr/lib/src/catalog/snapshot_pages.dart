import 'package:grund/grund.dart';

import '../page/site_page.dart';
import '../site/page_snapshot.dart';

/// A page with the injector of the module that declared it.
typedef DeclaredPage = ({SitePage page, Injector injector});

/// The pages of a [PageSnapshot] as [DeclaredPage]s.
abstract final class SnapshotPages {
  /// Every page of every site, sorted by path.
  static List<DeclaredPage> all(
    PageSnapshot snapshot, {
    required List<String> pageSuffixes,
  }) => [
    for (final (:api, :pages) in snapshot.declared)
      for (final page in pages)
        (
          page: SitePage(
            site: api.site,
            page: page,
            path: api.fullPathOf(page),
            pageSuffixes: pageSuffixes,
          ),
          injector: api.injector,
        ),
  ]..sort((a, b) => a.page.path.compareTo(b.page.path));
}
