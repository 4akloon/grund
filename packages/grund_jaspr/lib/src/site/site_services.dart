import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import '../page/page_renderer.dart';
import '../sitemap/sitemap_handlers.dart';

/// The collaborators a `SiteApi` serves its routes with.
final class SiteServices {
  /// Bundles the collaborators.
  const SiteServices({
    required this.renderer,
    required this.nonPage,
    required this.config,
    required this.sitemap,
  });

  /// Renders the not-found page.
  final PageRenderer renderer;

  /// Tells pages from file requests.
  final NonPageRequests nonPage;

  /// The configuration.
  final JasprConfig config;

  /// Answers the sitemap routes.
  final SitemapHandlers sitemap;
}
