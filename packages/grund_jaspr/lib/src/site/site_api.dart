import 'package:grund_http/grund_http.dart';

import '../page/page_renderer.dart';
import 'page_site.dart';

/// The fallback route of a site: everything below its path that no page
/// matches is the site's `notFound()`.
final class SiteApi<S extends PageSite> extends HttpApi {
  /// Creates the API of [site] in the module of [injector].
  SiteApi(super.injector, this.site);

  /// The site.
  final S site;

  /// The type of the site this API belongs to.
  Type get siteType => S;

  @override
  String get path => site.path;

  @override
  List<HookRef<HttpHook>> get use => const [];

  @override
  List<Route> get routes => [Route.get('/*', _notFound, use: site.use)];

  Future<HttpResponse> _notFound(HttpCtx c) => injector<PageRenderer>().render(
    c,
    site.shell(site.notFound()),
    status: StatusCode.notFound,
  );
}
