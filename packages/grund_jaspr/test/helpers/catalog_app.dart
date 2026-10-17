import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;

import 'pages_app.dart';
import 'sites.dart';
import 'validation_sites.dart';

/// Declares the site [S] and the [pages] under it.
final class CatalogPagesModule<S extends PageSite> extends Module {
  /// Creates the module for the site made by [create].
  const CatalogPagesModule(this.create, this.pages);

  /// Makes the site.
  final S Function(Injector) create;

  /// The pages of the site.
  final List<Page> pages;

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<S>(create),
    Singleton<AdminGuard>((_) => const AdminGuard(), dependsOn: const []),
    Singleton<CurrentUserHook>(
      (_) => const CurrentUserHook(),
      dependsOn: const [],
    ),
    Pages.under<S>((_) => pages),
  ];
}

/// A page whose body is a heading naming its [path], so a response tells
/// which page served it.
Page markedPage(
  String path, {
  PageMeta meta = const PageMeta(),
  PageHooks hooks = const PageHooks(),
  List<PageExtension> extensions = const [],
}) => Page(
  path,
  meta: meta,
  hooks: hooks,
  extensions: extensions,
  build: (_) =>
      Component.element(tag: 'h1', children: [Component.text('id:$path')]),
);

/// A page that has no navigation entry unless [nav] is given.
Page navPage(String path, {String title = '', PageNav? nav}) => markedPage(
  path,
  meta: PageMeta(title: title, nav: nav),
);

/// An extension that marks a page as markdown-like.
final class MarkdownLike extends PageExtension {
  /// Creates the extension.
  const MarkdownLike();
}

/// Another extension, to check the filter by type.
final class OtherExtension extends PageExtension {
  /// Creates the extension.
  const OtherExtension();
}

/// Starts the modules with `JasprModule` and returns the catalog.
Future<PageCatalog> startCatalog(
  List<Module> modules, {
  JasprConfig config = const JasprConfig(),
}) async {
  final app = await StartedPagesApp.start([
    JasprModule(config: config),
    ...modules,
  ]);
  return app.injector<PageCatalog>();
}

/// Starts [modules] and returns the application, for tests that need both
/// the client and the catalog.
Future<TestApp> startCatalogApp(
  List<Module> modules, {
  JasprConfig config = const JasprConfig(),
}) => StartedPagesApp.start([JasprModule(config: config), ...modules]);

/// The sites used by the catalog tests: public, admin and a site that
/// extends the admin site.
List<Module> sampleSiteModules() => [
  CatalogPagesModule<PublicSite>(PublicSite.new, [
    navPage('/', title: 'Home', nav: const PageNav(order: 1)),
    navPage('/about', title: 'About', nav: const PageNav(order: 2)),
    navPage(
      '/blog',
      title: 'Blog',
      nav: const PageNav(label: 'Articles'),
    ),
    navPage('/contact'),
    markedPage('/projects/:slug'),
    markedPage('/projects/new'),
  ]),
  CatalogPagesModule<AdminSite>(AdminSite.new, [
    navPage('/', title: 'Dashboard', nav: const PageNav()),
    markedPage('/users/:id'),
  ]),
  CatalogPagesModule<SuperAdminSite>(SuperAdminSite.new, [
    navPage('/', title: 'Super', nav: const PageNav()),
  ]),
];
