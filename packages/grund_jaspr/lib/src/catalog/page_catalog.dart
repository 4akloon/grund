import '../error/page_runtime_error.dart';
import '../jaspr_config.dart';
import '../page/page_extension.dart';
import '../page/page_match.dart';
import '../page/site_page.dart';
import '../site/page_registry.dart';
import '../site/page_site.dart';
import '../site/page_snapshot.dart';
import 'nav_item.dart';
import 'navigation_builder.dart';
import 'snapshot_index.dart';

/// The pages of the running application: per site, as navigation, by URL
/// and by extension.
///
/// It reads the snapshot of the pages runner, so it follows hot reloads.
/// Every read before the application has started throws
/// [PageCatalogNotReadyError].
final class PageCatalog {
  /// Reads the snapshot held by [_registry]; [config] decides what is a
  /// file request and where the static files lie.
  PageCatalog(this._registry, JasprConfig config)
    : _index = SnapshotIndex(config);

  final PageRegistry _registry;
  final SnapshotIndex _index;

  PageSnapshot get _snapshot =>
      _registry.current ?? (throw const PageCatalogNotReadyError());

  /// The pages of the site [S], sorted by path.
  ///
  /// Only the site of exactly the type [S]: a subtype's pages are not
  /// included.
  List<SitePage> pagesOf<S extends PageSite>() => _index.pagesOf(_snapshot, S);

  /// The navigation of the site [S]: by `order`, then `label`, then `path`.
  ///
  /// A page is listed when it has `meta.nav`. A page with its own
  /// `hooks.use` is left out unless `meta.sitemap.included` is `true`, and
  /// `included: false` always leaves it out. A page whose path has a
  /// `:param` has no concrete URL and is left out.
  List<NavItem> navOf<S extends PageSite>() =>
      NavigationBuilder.of(pagesOf<S>());

  /// The page that would serve [uri] and its path parameters, or `null`
  /// where no page would: a file request, a URL of the static files, or no
  /// page with that path.
  ///
  /// The matching follows the HTTP router: a literal beats a `:param`,
  /// empty segments are dropped, segments are percent-decoded and the case
  /// matters. It knows only pages, the static layer and the sites: a route
  /// of a user `HttpApi`, such as `/api/x`, is not considered.
  PageMatch? match(Uri uri) => _index.match(_snapshot, uri);

  /// The pages that carry an extension of type [T].
  List<SitePage> pagesWith<T extends PageExtension>() => [
    for (final page in _index.pages(_snapshot))
      if (page.page.extensions.any((extension) => extension is T)) page,
  ];
}
