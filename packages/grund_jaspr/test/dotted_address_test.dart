import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/no_injector.dart';
import 'helpers/sitemap_app.dart';
import 'helpers/sitemap_sites.dart';

final class _NeverSite extends PageSite {
  _NeverSite(super.injector);

  @override
  Uri? get baseUrl => Uri.parse('https://x.test');
}

final class _AlwaysSite extends PageSite {
  _AlwaysSite(super.injector);

  @override
  Uri? get baseUrl => Uri.parse('https://x.test');

  @override
  TrailingSlash get trailingSlash => TrailingSlash.always;
}

final class _IgnoreSite extends PageSite {
  _IgnoreSite(super.injector);

  @override
  Uri? get baseUrl => Uri.parse('https://x.test');

  @override
  TrailingSlash get trailingSlash => TrailingSlash.ignore;
}

const _slugs = ['v1.2', 'v12', 'feed.xml'];

List<Page> _pages(List<String> builds) => [
  markedPage('/'),
  Page(
    '/:slug',
    meta: PageMeta(sitemap: PageSitemap(entries: slugEntries(_slugs))),
    build: (c) {
      builds.add(c.path.string('slug'));
      return const Component.text('slug');
    },
  ),
  navPage('/v2.0', title: 'Dotted', nav: const PageNav()),
];

void _register<S extends PageSite>(
  String name,
  S Function(Injector) create,
  TrailingSlash policy,
) {
  group('a dotted slug under $name', () {
    late SitemapHarness h;
    final builds = <String>[];
    setUp(() async {
      builds.clear();
      h = await startSitemap([CatalogPagesModule<S>(create, _pages(builds))]);
    });

    test('the address with a slash is served', () async {
      final response = await h.client.get('/v1.2/');
      expect(response.status, 200);
      expect(builds, ['v1.2']);
    });

    test('the address without a slash is a file request', () async {
      final response = await h.client.get('/v1.2');
      expect(response.status, 404);
      expect(response.text, contains('file_not_found'));
      expect(builds, isEmpty);
    });

    test('PageMatch path and url keep the slash', () {
      final match = PageMatch(
        page: SitePage(
          site: create(const NoInjector()),
          page: _pages([])[1],
          path: '/:slug',
        ),
        params: const {'slug': 'v1.2'},
      );
      expect(match.path, '/v1.2/');
      expect(match.url.toString(), 'https://x.test/v1.2/');
    });

    test('the sitemap and the navigation use the slash', () async {
      final body = (await h.client.get('/sitemap.xml')).text;
      expect(body, contains('<loc>https://x.test/v1.2/</loc>'));
      final nav = h.catalog.navOf<S>().map((item) => item.path);
      expect(nav, contains('/v2.0/'));
    });

    test('a plain slug follows the policy', () async {
      final body = (await h.client.get('/sitemap.xml')).text;
      final slash = policy == TrailingSlash.always ? '/' : '';
      expect(body, contains('<loc>https://x.test/v12$slash</loc>'));
    });

    test('a page suffix is not a file', () async {
      final body = (await h.client.get('/sitemap.xml')).text;
      expect(body, contains('<loc>https://x.test/feed.xml</loc>'));
      expect((await h.client.get('/feed.xml')).status, 200);
    });
  });
}

void main() {
  _register('never', _NeverSite.new, TrailingSlash.never);
  _register('always', _AlwaysSite.new, TrailingSlash.always);
  _register('ignore', _IgnoreSite.new, TrailingSlash.ignore);
}
