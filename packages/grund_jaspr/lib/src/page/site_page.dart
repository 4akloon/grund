import '../site/page_site.dart';
import 'page.dart';

/// A [Page] together with the site that serves it.
final class SitePage {
  /// Creates the pair.
  const SitePage({required this.site, required this.page, required this.path});

  /// The site that serves [page].
  final PageSite site;

  /// The declared page.
  final Page page;

  /// The full path: the site path followed by the page path.
  final String path;
}
