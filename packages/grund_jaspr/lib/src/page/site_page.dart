import '../jaspr_config.dart';
import '../site/page_site.dart';
import 'page.dart';

/// A [Page] together with the site that serves it.
final class SitePage {
  /// Creates the pair.
  const SitePage({
    required this.site,
    required this.page,
    required this.path,
    this.pageSuffixes = JasprConfig.defaultPageSuffixes,
  });

  /// The site that serves [page].
  final PageSite site;

  /// The declared page.
  final Page page;

  /// The full path: the site path followed by the page path.
  final String path;

  /// The `pageSuffixes` of the configuration the site runs under; they tell
  /// a canonical address from a file request.
  final List<String> pageSuffixes;
}
