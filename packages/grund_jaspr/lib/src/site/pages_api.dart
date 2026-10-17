import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart' hide Key;

import '../error/page_declaration_error.dart';
import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import '../page/page.dart';
import '../page/page_match.dart';
import '../page/page_path.dart';
import '../page/page_renderer.dart';
import '../page/site_page.dart';
import 'hook_resolver.dart';
import 'page_site.dart';

/// The page routes of one `Pages.under` declaration.
final class PagesApi<S extends PageSite> extends HttpApi {
  /// Creates the API; [_declare] lists the pages and is called on every
  /// [pages] read.
  PagesApi(
    super.injector,
    this.site,
    this._renderer,
    this._nonPage,
    this._config,
    this._declare,
  );

  /// The site the pages belong to.
  final S site;

  final PageRenderer _renderer;
  final NonPageRequests _nonPage;
  final JasprConfig _config;
  final List<Page> Function(Injector) _declare;

  /// The type of the site this API belongs to.
  Type get siteType => S;

  @override
  String get path => site.path;

  /// The declared pages, listed again on every call.
  List<Page> get pages => _declare(injector);

  @override
  List<Route> get routes => [for (final page in pages) _route(page)];

  Route _route(Page page) {
    _checkNotReserved(page);
    return Route.get(
      page.path,
      (c) => _serve(c, page),
      use: const HookResolver().forPage(
        site: site,
        page: page,
        fullPath: fullPathOf(page),
      ),
      name: 'GET ${fullPathOf(page)}',
    );
  }

  // Throws when a page would take over a static file URL.
  void _checkNotReserved(Page page) {
    final path = fullPathOf(page);
    final staticPath = _config.staticPath;
    if (path == staticPath || path.startsWith('$staticPath/')) {
      throw ReservedPagePathError(
        path: path,
        reason: 'static files are served under "$staticPath"',
      );
    }
    for (final file in _config.rootFiles) {
      if (path == '/$file') {
        throw ReservedPagePathError(
          path: path,
          reason: 'the static file "$file" is served at the root',
        );
      }
    }
  }

  /// The path the router registers for [page]: the root page of a site with
  /// a prefix is the prefix itself, without a trailing slash.
  String fullPathOf(Page page) {
    final relative = PagePath.parse(page.path).normalized;
    if (relative != '/') return '${site.path}$relative';
    return site.path.isEmpty ? '/' : site.path;
  }

  Future<HttpResponse> _serve(HttpCtx c, Page page) async {
    final uri = c.request.uri;
    if (!_nonPage.isPageRequest(uri)) _nonPage.notFound(uri);
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
        page: SitePage(site: site, page: page, path: fullPathOf(page)),
        params: {
          for (final name in PagePath.parse(page.path).paramNames)
            name: c.path.string(name),
        },
      ),
    );
  }
}
