import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart' hide Key;

import '../page/page.dart';
import '../page/page_match.dart';
import '../page/page_path.dart';
import '../page/page_renderer.dart';
import '../page/site_page.dart';
import 'page_site.dart';

/// The page routes of one `Pages.under` declaration.
final class PagesApi<S extends PageSite> extends HttpApi {
  /// Creates the API; [_declare] lists the pages and is called on every
  /// [pages] read.
  PagesApi(super.injector, this.site, this._renderer, this._declare);

  /// The site the pages belong to.
  final S site;

  final PageRenderer _renderer;
  final List<Page> Function(Injector) _declare;

  /// The type of the site this API belongs to.
  Type get siteType => S;

  @override
  String get path => site.path;

  /// The declared pages, listed again on every call.
  List<Page> get pages => _declare(injector);

  @override
  List<Route> get routes => [
    for (final page in pages)
      Route.get(
        page.path,
        (c) => _serve(c, page),
        use: [...site.use, ...page.hooks.use],
        name: 'GET ${site.path}${page.path}',
      ),
  ];

  Future<HttpResponse> _serve(HttpCtx c, Page page) async {
    final Component content;
    try {
      content = await page.build(c);
    } on NotFoundException {
      return _renderer.render(
        c,
        site.shell(site.notFound()),
        status: StatusCode.notFound,
      );
    }
    return _renderer.render(
      c,
      site.shell(content),
      match: PageMatch(
        page: SitePage(
          site: site,
          page: page,
          path: '${site.path}${page.path}',
        ),
        params: {
          for (final name in PagePath.parse(page.path).paramNames)
            name: c.path.string(name),
        },
      ),
    );
  }
}
