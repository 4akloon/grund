import '../error/page_declaration_error.dart';
import '../jaspr_config.dart';
import '../page/page.dart';
import '../page/page_path.dart';
import 'page_site.dart';
import 'reserved_paths.dart';

/// Rejects a page declaration that contradicts the site or the framework.
abstract final class PageDeclarationCheck {
  /// Throws [ReservedPagePathError] when [page] at [fullPath] would take a
  /// URL the framework serves, [UnusedPageEntriesError] when it lists
  /// sitemap entries without parameters and [UndecidedPageSitemapError]
  /// when a parameterised page of a site with a sitemap does not say how it
  /// appears in it.
  static void check(
    Page page, {
    required PageSite site,
    required String fullPath,
    required JasprConfig config,
  }) {
    final reason = ReservedPaths.reasonFor(
      fullPath,
      sitePath: site.path,
      config: config,
    );
    if (reason != null) {
      throw ReservedPagePathError(path: fullPath, reason: reason);
    }
    final entries = page.meta.sitemap.entries;
    final hasParams = PagePath.parse(page.path).hasParams;
    if (!hasParams && entries != null) throw UnusedPageEntriesError(fullPath);
    final decided = entries != null || page.meta.sitemap.included == false;
    if (hasParams && site.sitemapBaseUrl != null && !decided) {
      throw UndecidedPageSitemapError(fullPath);
    }
  }
}
