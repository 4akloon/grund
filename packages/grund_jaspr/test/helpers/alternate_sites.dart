import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;

import 'catalog_app.dart';
import 'sites.dart';

/// A root site without a base URL.
final class PlainAltSite extends PageSite {
  /// Creates the site.
  PlainAltSite(super.injector);
}

/// A root site with a base URL.
final class BaseAltSite extends PageSite {
  /// Creates the site.
  BaseAltSite(super.injector);

  @override
  Uri? get baseUrl => Uri.parse('https://x.test');
}

/// A root site with a base URL and `always`.
final class AlwaysAltSite extends PageSite {
  /// Creates the site.
  AlwaysAltSite(super.injector);

  @override
  Uri? get baseUrl => Uri.parse('https://x.test');

  @override
  TrailingSlash get trailingSlash => TrailingSlash.always;
}

/// A site under `/docs`.
final class DocsAltSite extends PageSite {
  /// Creates the site.
  DocsAltSite(super.injector);

  @override
  String get path => '/docs';
}

/// A site that requires Markdown of every page.
final class RequiringAltSite extends PageSite {
  /// Creates the site.
  RequiringAltSite(super.injector);

  @override
  List<String> get requiredAlternates => const ['text/markdown'];
}

/// A site under `/admin` guarded by [AdminGuard], which a page may skip.
final class GuardedAltSite extends AdminSite {
  /// Creates the site.
  GuardedAltSite(super.injector);

  @override
  List<Type> get skippableHooks => const [AdminGuard];
}

/// Adds a `vary` token and a `link` to the response.
final class HeaderHook extends HttpHook {
  /// Creates the hook.
  const HeaderHook();

  @override
  void before(HttpCtx c) {
    c.response.headers
      ..add('vary', 'cookie')
      ..add('link', '</hook>; rel="preload"');
  }
}

/// Pages `/`, `/about` and `/projects/:slug` with Markdown; `nope` is unknown.
List<Page> markdownPages() => [
  _page('/', 'home'),
  _page('/about', 'about'),
  _page('/projects/:slug', 'project', unknownSlug: 'nope'),
];

Page _page(String path, String name, {String? unknownSlug}) => Page(
  path,
  meta: const PageMeta(sitemap: PageSitemap(included: false)),
  alternates: [
    PageAlternate.markdown((c, match) {
      final slug = match.params['slug'];
      if (slug != null && slug == unknownSlug) throw const NotFoundException();
      return '# $name ${slug ?? ''}'.trimRight();
    }),
  ],
  build: (c) {
    if (c.path.stringOrNull('slug') == unknownSlug && unknownSlug != null) {
      throw const NotFoundException();
    }
    return Component.element(
      tag: 'h1',
      children: [Component.text('html $name')],
    );
  },
);

/// The module of [S] with [pages].
CatalogPagesModule<S> altModule<S extends PageSite>(
  S Function(Injector) create, [
  List<Page>? pages,
]) => CatalogPagesModule<S>(create, pages ?? markdownPages());
