import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;

import 'catalog_app.dart';

/// A root site with the default policy, `never`.
final class NeverSite extends PageSite {
  /// Creates the site.
  NeverSite(super.injector);
}

/// A root site with `always`.
final class AlwaysSite extends PageSite {
  /// Creates the site.
  AlwaysSite(super.injector);

  @override
  TrailingSlash get trailingSlash => TrailingSlash.always;

  @override
  Uri? get baseUrl => Uri.parse('https://x.test');
}

/// A root site with `ignore`.
final class IgnoreSite extends PageSite {
  /// Creates the site.
  IgnoreSite(super.injector);

  @override
  TrailingSlash get trailingSlash => TrailingSlash.ignore;
}

/// A site under `/docs` with `never`.
final class DocsNeverSite extends PageSite {
  /// Creates the site.
  DocsNeverSite(super.injector);

  @override
  String get path => '/docs';
}

/// A site under `/docs` with `always`.
final class DocsAlwaysSite extends PageSite {
  /// Creates the site.
  DocsAlwaysSite(super.injector);

  @override
  String get path => '/docs';

  @override
  TrailingSlash get trailingSlash => TrailingSlash.always;
}

/// Pages `/`, `/about`, `/feed.xml` and `/projects/:slug` whose builder
/// bumps [builds].
List<Page> slashPages(List<String> builds) => [
  markedPage('/'),
  markedPage('/about'),
  markedPage('/feed.xml'),
  Page(
    '/projects/:slug',
    meta: const PageMeta(sitemap: PageSitemap(included: false)),
    build: (c) {
      builds.add(c.path.string('slug'));
      return const Component.text('project');
    },
  ),
];

/// The module of [S] with [slashPages].
CatalogPagesModule<S> slashModule<S extends PageSite>(
  S Function(Injector) create,
  List<String> builds,
) => CatalogPagesModule<S>(create, slashPages(builds));
