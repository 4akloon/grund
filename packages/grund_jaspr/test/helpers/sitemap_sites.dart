import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'catalog_app.dart';
import 'sites.dart';

/// A site with a sitemap at `https://x.test`.
final class MapSite extends PageSite {
  /// Creates the site.
  MapSite(super.injector);

  @override
  Uri? get sitemapBaseUrl => Uri.parse('https://x.test');
}

/// A guarded site that also asks for a sitemap: an invalid declaration.
final class GuardedMapSite extends PageSite {
  /// Creates the site.
  GuardedMapSite(super.injector);

  @override
  List<HookRef<HttpHook>> get use => const [HookRef<AdminGuard>.type()];

  @override
  Uri? get sitemapBaseUrl => Uri.parse('https://x.test');
}

/// A site under `/docs` with a sitemap.
final class DocsMapSite extends PageSite {
  /// Creates the site.
  DocsMapSite(super.injector);

  @override
  String get path => '/docs';

  @override
  Uri? get sitemapBaseUrl => Uri.parse('https://x.test');
}

/// Entries for the parameter `slug`, one per name.
SitemapEntries slugEntries(
  List<String> slugs, {
  void Function(Injector injector)? onLoad,
}) => SitemapEntries.all((injector) async {
  onLoad?.call(injector);
  return [
    for (final slug in slugs) SitemapEntry(params: {'slug': slug}),
  ];
});

/// A page of the sitemap tests.
Page mapPage(String path, {PageSitemap sitemap = const PageSitemap()}) =>
    markedPage(path, meta: PageMeta(sitemap: sitemap));

/// A [MapSite] module with a root page and [pages].
CatalogPagesModule<MapSite> mapModule(List<Page> pages) =>
    CatalogPagesModule<MapSite>(MapSite.new, [mapPage('/'), ...pages]);

/// Matches [T], whether the start failure wraps it or not.
Matcher declaredError<T extends Object>() =>
    predicate<Object>((error) => error is T || '$error'.contains('$T'), 'a $T');
