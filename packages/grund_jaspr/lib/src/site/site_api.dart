import 'package:grund_http/grund_http.dart';

import '../error/site_declaration_error.dart';
import 'page_responder.dart';
import 'page_site.dart';
import 'site_declaration_check.dart';
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
    SiteDeclarationCheck.check(site, siteType: S, config: _services.config);
  }

  /// The site.
  final S site;

  final SiteServices _services;

  PageResponder get _responder => PageResponder(_services);

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

  Future<HttpResponse> _notFound(HttpCtx c) async {
    if (!_services.nonPage.isPageRequest(c.request.uri)) {
      _services.nonPage.notFound(c.request.uri);
    }
    return _responder.notFound(c, site);
  }
}
