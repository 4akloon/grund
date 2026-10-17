import 'package:grund_http/grund_http.dart';

import '../error/site_declaration_error.dart';
import '../page/page_path.dart';
import 'page_site.dart';
import 'site_services.dart';

/// The fallback route of a site: everything below its path that no page
/// matches is the site's `notFound()`.
final class SiteApi<S extends PageSite> extends HttpApi {
  /// Creates the API of [site] in the module of [injector]; throws
  /// [InvalidSitePathError] when the site path is not `''` or
  /// `/segment[/segment]` of literals, lies on the `staticPath` of the
  /// configuration or is a `rootFiles` entry, and [GuardedSiteSitemapError]
  /// when it has hooks and a sitemap.
  SiteApi(super.injector, this.site, this._services) {
    final config = _services.config;
    final path = site.path;
    PagePath.checkSitePath(path);
    if (config.rootFiles.any((file) => path == '/$file')) {
      throw InvalidSitePathError(
        path: path,
        reason: 'it is the root file "${path.substring(1)}"',
      );
    }
    if (path == config.staticPath || path.startsWith('${config.staticPath}/')) {
      throw InvalidSitePathError(
        path: path,
        reason: 'it is the static path "${config.staticPath}" or lies under it',
      );
    }
    if (site.use.isNotEmpty && site.sitemapBaseUrl != null) {
      throw GuardedSiteSitemapError(S);
    }
  }

  /// The site.
  final S site;

  final SiteServices _services;

  /// The type of the site this API belongs to.
  Type get siteType => S;

  @override
  String get path => site.path;

  @override
  List<Route> get routes => [
    // The sitemap routes carry no hooks: a site with hooks cannot have a
    // sitemap (checked in the constructor), so none can be skipped.
    if (site.sitemapBaseUrl != null) ...[
      Route.get('/sitemap.xml', (_) => _services.sitemap.document(site)),
      Route.get(
        '/sitemap/:chunk',
        (c) => _services.sitemap.chunk(site, c.path.string('chunk')),
      ),
    ],
    Route.get('/*', _notFound, use: site.use),
  ];

  Future<HttpResponse> _notFound(HttpCtx c) {
    if (!_services.nonPage.isPageRequest(c.request.uri)) {
      return _services.nonPage.answer(c, _services.extensions.of(S));
    }
    return _services.renderer.render(
      c,
      site.shell(site.notFound()),
      status: StatusCode.notFound,
    );
  }
}
