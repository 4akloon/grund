import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/no_injector.dart';
import 'helpers/sitemap_sites.dart';
import 'helpers/slash_sites.dart';

PageMatch _match<S extends PageSite>(
  S site,
  String path,
  Map<String, String> params,
) => PageMatch(
  page: SitePage(site: site, page: markedPage(path), path: path),
  params: params,
);

final class _BadBase extends PageSite {
  _BadBase(super.injector, this.base);

  final Uri base;

  @override
  Uri? get baseUrl => base;
}

void main() {
  const injector = NoInjector();

  group('PageMatch', () {
    test('path follows the policy of the site', () {
      expect(
        _match(NeverSite(injector), '/a/:n', {'n': 'a b/c'}).path,
        '/a/a%20b%2Fc',
      );
      expect(
        _match(AlwaysSite(injector), '/a/:n', {'n': 'a b/c'}).path,
        '/a/a%20b%2Fc/',
      );
      expect(_match(IgnoreSite(injector), '/a', const {}).path, '/a');
    });

    test('url needs a baseUrl', () {
      expect(_match(NeverSite(injector), '/a', const {}).url, isNull);
      expect(
        _match(AlwaysSite(injector), '/a', const {}).url,
        Uri.parse('https://x.test/a/'),
      );
    });

    test('a missing parameter is an ArgumentError', () {
      expect(
        () => _match(NeverSite(injector), '/projects/:slug', const {}).path,
        throwsArgumentError,
      );
    });
  });

  test('navOf spells the paths by the policy', () async {
    final catalog = await startCatalog([
      CatalogPagesModule<AlwaysSite>(AlwaysSite.new, [
        markedPage('/'),
        navPage('/about', nav: const PageNav()),
      ]),
    ]);

    expect([for (final i in catalog.navOf<AlwaysSite>()) i.path], ['/about/']);
  });

  test('sitemap locations end with the slash under always', () async {
    final catalog = await startCatalog([
      CatalogPagesModule<AlwaysSite>(AlwaysSite.new, [
        markedPage('/'),
        markedPage('/about'),
      ]),
    ]);

    final urls = await catalog.sitemapOf<AlwaysSite>().toList();

    expect(
      [for (final u in urls) u.location.toString()],
      ['https://x.test/', 'https://x.test/about/'],
    );
  });

  group('baseUrl check', () {
    final cases = {
      'ftp://x': 'scheme',
      'https:///': 'host',
      'https://x.test/app': 'path',
      'https://x.test?q': 'query',
      'https://x.test#f': 'fragment',
      'https://u@x.test': 'user',
    };
    cases.forEach((url, word) {
      test('$url is rejected', () async {
        await expectLater(
          startCatalog([
            CatalogPagesModule<_BadBase>((i) => _BadBase(i, Uri.parse(url)), [
              markedPage('/'),
            ]),
          ]),
          throwsA(
            isA<InvalidSiteBaseUrlError>().having(
              (e) => e.reason,
              'reason',
              contains(word),
            ),
          ),
        );
      });
    });

    test('https://x.test/ is accepted', () async {
      await startCatalog([
        CatalogPagesModule<_BadBase>(
          (i) => _BadBase(i, Uri.parse('https://x.test/')),
          [markedPage('/')],
        ),
      ]);
    });
  });

  test('GuardedSiteSitemapError names baseUrl', () {
    expect(const GuardedSiteSitemapError(MapSite).message, contains('baseUrl'));
  });

  test('match finds a page by a URL with a trailing slash', () async {
    final catalog = await startCatalog([
      CatalogPagesModule<NeverSite>(NeverSite.new, [
        markedPage('/'),
        markedPage('/login'),
      ]),
    ]);

    expect(catalog.match(Uri.parse('/login/'))?.page.path, '/login');
  });
}
