import 'package:grund_http/grund_http.dart';

import '../error/site_declaration_error.dart';
import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import '../page/page_renderer.dart';
import 'page_site.dart';

/// The fallback route of a site: everything below its path that no page
/// matches is the site's `notFound()`.
final class SiteApi<S extends PageSite> extends HttpApi {
  /// Creates the API of [site] in the module of [injector]; throws
  /// [InvalidSitePathError] when the site lies on the `staticPath` of
  /// [config] and [GuardedSiteSitemapError] when it has hooks and a sitemap.
  SiteApi(
    super.injector,
    this.site,
    this._renderer,
    this._nonPage,
    JasprConfig config,
  ) {
    final path = site.path;
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

  final PageRenderer _renderer;
  final NonPageRequests _nonPage;

  /// The type of the site this API belongs to.
  Type get siteType => S;

  @override
  String get path => site.path;

  @override
  List<Route> get routes => [Route.get('/*', _notFound, use: site.use)];

  Future<HttpResponse> _notFound(HttpCtx c) {
    final uri = c.request.uri;
    if (!_nonPage.isPageRequest(uri)) _nonPage.notFound(uri);
    return _renderer.render(
      c,
      site.shell(site.notFound()),
      status: StatusCode.notFound,
    );
  }
}
