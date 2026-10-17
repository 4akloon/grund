import 'page_meta.dart';
import 'site_page.dart';

/// A page that a request matched, with the values of its path parameters.
final class PageMatch {
  /// Creates the match.
  const PageMatch({required this.page, this.params = const {}});

  /// The matched page.
  final SitePage page;

  /// The path parameters by name.
  final Map<String, String> params;

  /// The title, navigation and sitemap settings of the matched page.
  PageMeta get meta => page.page.meta;
}
