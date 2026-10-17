import 'package:grund/grund.dart';

import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import '../page/page.dart';
import '../page/page_renderer.dart';
import 'page_site.dart';
import '../sitemap/sitemap_handlers.dart';
import 'pages_api.dart';
import 'site_api.dart';
import 'site_services.dart';

/// Bindings that declare sites and pages in a module.
///
/// ```dart
/// final class AdminModule extends Module {
///   const AdminModule();
///
///   @override
///   List<Binding<Object>> get bindings => [
///     ...Pages.site<AdminSite>(AdminSite.new),
///     Pages.under<AdminSite>((i) => [Page('/', build: (c) => Home())]),
///   ];
/// }
/// ```
abstract final class Pages {
  /// Declares the site [S]: the site itself and its fallback route.
  ///
  /// Export `Key<S>()` for modules that declare pages under it.
  static List<Binding<Object>> site<S extends PageSite>(
    S Function(Injector) create,
  ) => [
    Singleton<S>(create, dependsOn: const []),
    Singleton<SiteApi<S>>(
      (i) => SiteApi<S>(
        i,
        i<S>(),
        SiteServices(
          renderer: i<PageRenderer>(),
          nonPage: i<NonPageRequests>(),
          config: i<JasprConfig>(),
          sitemap: i<SitemapHandlers>(),
        ),
      ),
      dependsOn: [
        Key<S>(),
        Key<PageRenderer>(),
        Key<NonPageRequests>(),
        Key<JasprConfig>(),
        Key<SitemapHandlers>(),
      ],
    ),
  ];

  /// Declares the pages of the site [S]; [pages] is called again after a hot
  /// reload.
  static Binding<Object> under<S extends PageSite>(
    List<Page> Function(Injector) pages,
  ) => Singleton<PagesApi<S>>(
    (i) => PagesApi<S>(
      i,
      i<S>(),
      i<PageRenderer>(),
      i<NonPageRequests>(),
      i<JasprConfig>(),
      pages,
    ),
    dependsOn: [
      Key<S>(),
      Key<PageRenderer>(),
      Key<NonPageRequests>(),
      Key<JasprConfig>(),
    ],
  );
}
