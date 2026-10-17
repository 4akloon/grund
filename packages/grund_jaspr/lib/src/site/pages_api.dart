import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import '../page/page.dart';
import '../page/page_address.dart';
import '../page/page_alternate.dart';
import '../page/page_match.dart';
import '../page/page_path.dart';
import '../page/site_page.dart';
import 'hook_resolver.dart';
import 'page_declaration_check.dart';
import 'page_responder.dart';
import 'page_site.dart';
import 'site_services.dart';

/// The page routes of one `Pages.under` declaration.
final class PagesApi<S extends PageSite> extends HttpApi {
  /// Creates the API; [_declare] lists the pages and is called on every
  /// [pages] read.
  PagesApi(super.injector, this.site, this._services, this._declare);

  /// The site the pages belong to.
  final S site;

  final SiteServices _services;

  PageResponder get _responder => PageResponder(_services);
  final List<Page> Function(Injector) _declare;

  /// The type of the site this API belongs to.
  Type get siteType => S;

  @override
  String get path => site.path;

  /// The declared pages, listed again on every call.
  List<Page> get pages => _declare(injector);

  @override
  List<Route> get routes => [for (final page in pages) ..._routesOf(page)];

  List<Route> _routesOf(Page page) {
    final fullPath = fullPathOf(page);
    PageDeclarationCheck.check(
      page,
      site: site,
      fullPath: fullPath,
      config: _services.config,
    );
    final hooks = const HookResolver().forPage(
      site: site,
      page: page,
      fullPath: fullPath,
    );
    return [
      Route.get(
        page.path,
        (c) => _serve(c, page, isGuarded: hooks.isNotEmpty),
        use: hooks,
        name: 'GET $fullPath',
      ),
      for (final alternate in page.alternates)
        _alternateRoute(page, alternate, hooks),
    ];
  }

  Route _alternateRoute(
    Page page,
    PageAlternate alternate,
    List<HookRef<HttpHook>> hooks,
  ) {
    final pattern = PageAddress.alternatePatternOf(page.path, alternate.suffix);
    return Route.get(
      pattern,
      (c) => _responder.alternate(
        c,
        site: site,
        alternate: alternate,
        match: _matchOf(c, page),
        isGuarded: hooks.isNotEmpty,
      ),
      use: hooks,
      name: 'GET ${site.path}$pattern',
    );
  }

  /// The path the router registers for [page]: the root page of a site with
  /// a prefix is the prefix itself, without a trailing slash.
  String fullPathOf(Page page) {
    final relative = PagePath.parse(page.path).normalized;
    if (relative != '/') return '${site.path}$relative';
    return site.path.isEmpty ? '/' : site.path;
  }

  Future<HttpResponse> _serve(
    HttpCtx c,
    Page page, {
    required bool isGuarded,
  }) => _responder.page(
    c,
    site: site,
    page: page,
    match: _matchOf(c, page),
    isGuarded: isGuarded,
  );

  PageMatch _matchOf(HttpCtx c, Page page) => PageMatch(
    page: SitePage(
      site: site,
      page: page,
      path: fullPathOf(page),
      pageSuffixes: _services.config.pageSuffixes,
    ),
    params: {
      for (final name in PagePath.parse(page.path).paramNames)
        name: c.path.string(name),
    },
  );
}
