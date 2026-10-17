import '../error/page_runtime_error.dart';
import '../jaspr_config.dart';
import '../page/page_match.dart';
import '../page/site_page.dart';
import '../site/page_registry.dart';
import '../site/page_site.dart';
import '../site/page_snapshot.dart';
import '../sitemap/sitemap_chunk_cache.dart';
import '../sitemap/sitemap_url.dart';
import 'nav_item.dart';
import 'navigation_builder.dart';
import 'sitemap_source.dart';
import 'snapshot_index.dart';

/// The pages of the running application: per site, as navigation and by URL.
///
/// It reads the snapshot of the pages runner, so it follows hot reloads.
/// Every read before the application has started throws
/// [PageCatalogNotReadyError].
final class PageCatalog {
  /// Reads the snapshot held by [_registry]; [config] decides what is a
  /// file request and where the static files lie.
  ///
  /// [index] and [sitemapCache] are shared with the sitemap routes when the
  /// module makes the catalog; alone, it has its own.
  PageCatalog(
    this._registry,
    JasprConfig config, {
    SnapshotIndex? index,
    SitemapChunkCache? sitemapCache,
  }) : _index = index ?? SnapshotIndex(config),
       _sitemap = SitemapSource(config),
       _sitemapCache =
           sitemapCache ??
           SitemapChunkCache(config.sitemapCacheLifetime, DateTime.now);

  final PageRegistry _registry;
  final SnapshotIndex _index;
  final SitemapSource _sitemap;
  final SitemapChunkCache _sitemapCache;

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

  /// The addresses of the sitemap of the site [S], by path: its static
  /// pages and the `entries` of its parameterised pages, loaded in chunks
  /// of `JasprConfig.sitemapChunkSize` while the stream is read.
  ///
  /// Empty when the site has no `sitemapBaseUrl`. A page with `included:
  /// false` or with its own `hooks.use` (unless `included: true`) is left
  /// out. Throws [PageEntriesMismatchError] when an entry's parameters are
  /// not those of the page path.
  Stream<SitemapUrl> sitemapOf<S extends PageSite>() =>
      _sitemap.urls(_index.declaredOf(_snapshot, S));

  /// Drops the cached sitemap plan and chunks, so the next sitemap request
  /// reads the `entries` again.
  void invalidateSitemap() => _sitemapCache.clear();

  /// The page that would serve [uri] and its path parameters, or `null`
  /// where no page would: a file request, a URL of the static files, or no
  /// page with that path.
  ///
  /// The matching follows the HTTP router: a literal beats a `:param`,
  /// empty segments are dropped, segments are percent-decoded and the case
  /// matters. It knows only pages, the static layer and the sites: a route
  /// of a user `HttpApi`, such as `/api/x`, is not considered.
  PageMatch? match(Uri uri) => _index.match(_snapshot, uri);
}
