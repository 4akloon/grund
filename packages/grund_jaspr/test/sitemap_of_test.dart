import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sites.dart';
import 'helpers/sitemap_sites.dart';

Future<List<String>> _locations(PageCatalog catalog) async => [
  await for (final url in catalog.sitemapOf<MapSite>()) url.location.toString(),
];

void main() {
  test('static pages and entries give absolute locations', () async {
    final catalog = await startCatalog([
      mapModule([
        mapPage('/about'),
        mapPage(
          '/projects/:slug',
          sitemap: PageSitemap(entries: slugEntries(['alpha', 'beta'])),
        ),
      ]),
    ]);

    expect(await _locations(catalog), [
      'https://x.test/',
      'https://x.test/about',
      'https://x.test/projects/alpha',
      'https://x.test/projects/beta',
    ]);
  });

  test('a page with included false is skipped', () async {
    final catalog = await startCatalog([
      mapModule([
        mapPage('/hidden', sitemap: const PageSitemap(included: false)),
      ]),
    ]);

    expect(await _locations(catalog), ['https://x.test/']);
  });

  test(
    'a page with its own hooks is skipped unless included is true',
    () async {
      final catalog = await startCatalog([
        mapModule([
          markedPage(
            '/private',
            hooks: const PageHooks(use: [HookRef<AdminGuard>.type()]),
          ),
          markedPage(
            '/shown',
            hooks: const PageHooks(use: [HookRef<AdminGuard>.type()]),
            meta: const PageMeta(sitemap: PageSitemap(included: true)),
          ),
        ]),
      ]);

      expect(await _locations(catalog), [
        'https://x.test/',
        'https://x.test/shown',
      ]);
    },
  );

  test('a site without sitemapBaseUrl gives an empty stream', () async {
    final catalog = await startCatalog([
      CatalogPagesModule<PublicSite>(PublicSite.new, [markedPage('/')]),
    ]);

    expect(await catalog.sitemapOf<PublicSite>().toList(), isEmpty);
  });

  test('the page settings apply to a static page', () async {
    final modified = DateTime.utc(2026, 3, 4);
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/about',
          sitemap: PageSitemap(
            lastModified: modified,
            changeFrequency: SitemapChangeFrequency.daily,
            priority: 0.8,
          ),
        ),
      ]),
    ]);

    final url = (await catalog.sitemapOf<MapSite>().toList())[1];

    expect(url.lastModified, modified);
    expect(url.changeFrequency, SitemapChangeFrequency.daily);
    expect(url.priority, 0.8);
  });

  test('an entry falls back to the page lastModified', () async {
    final pageDate = DateTime.utc(2026, 1, 1);
    final entryDate = DateTime.utc(2026, 2, 2);
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/p/:slug',
          sitemap: PageSitemap(
            lastModified: pageDate,
            changeFrequency: SitemapChangeFrequency.yearly,
            priority: 0.3,
            entries: SitemapEntries.all(
              (_) async => [
                SitemapEntry(params: {'slug': 'a'}, lastModified: entryDate),
                const SitemapEntry(params: {'slug': 'b'}),
              ],
            ),
          ),
        ),
      ]),
    ]);

    final urls = (await catalog.sitemapOf<MapSite>().toList()).skip(1).toList();

    expect(urls[0].lastModified, entryDate);
    expect(urls[1].lastModified, pageDate);
    expect(urls[1].changeFrequency, SitemapChangeFrequency.yearly);
    expect(urls[1].priority, 0.3);
  });

  test('parameter values are percent-encoded', () async {
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/p/:slug',
          sitemap: PageSitemap(entries: slugEntries(['a b/c', 'проєкт'])),
        ),
      ]),
    ]);

    final locations = await _locations(catalog);

    expect(locations[1], 'https://x.test/p/a%20b%2Fc');
    expect(
      locations[2],
      'https://x.test/p/%D0%BF%D1%80%D0%BE%D1%94%D0%BA%D1%82',
    );
  });

  test('a prefixed site resolves under its path', () async {
    final catalog = await startCatalog([
      CatalogPagesModule<DocsMapSite>(DocsMapSite.new, [
        mapPage('/'),
        mapPage('/intro'),
      ]),
    ]);

    final urls = await catalog.sitemapOf<DocsMapSite>().toList();

    expect(
      [for (final url in urls) url.location.toString()],
      ['https://x.test/docs', 'https://x.test/docs/intro'],
    );
  });

  test('paged entries are loaded in chunks of sitemapChunkSize', () async {
    final calls = <(int, int)>[];
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/p/:slug',
          sitemap: PageSitemap(
            entries: SitemapEntries.paged(
              count: (_) async => 120,
              load: (_, offset, limit) async {
                calls.add((offset, limit));
                return [
                  for (var i = offset; i < offset + limit; i++)
                    SitemapEntry(params: {'slug': '$i'}),
                ];
              },
            ),
          ),
        ),
      ]),
    ], config: const JasprConfig(sitemapChunkSize: 50));

    final urls = await catalog.sitemapOf<MapSite>().toList();

    expect(calls, [(0, 50), (50, 50), (100, 20)]);
    expect(urls, hasLength(121));
  });

  test('a page with no entries calls no load', () async {
    var loads = 0;
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/p/:slug',
          sitemap: PageSitemap(
            entries: SitemapEntries.paged(
              count: (_) async => 0,
              load: (_, _, _) async {
                loads++;
                return const [];
              },
            ),
          ),
        ),
      ]),
    ]);

    await catalog.sitemapOf<MapSite>().toList();

    expect(loads, 0);
  });

  test('the loader gets the injector of the declaring module', () async {
    Injector? seen;
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/p/:slug',
          sitemap: PageSitemap(
            entries: slugEntries(['a'], onLoad: (injector) => seen = injector),
          ),
        ),
      ]),
    ]);

    await catalog.sitemapOf<MapSite>().toList();

    expect(seen, isNotNull);
    expect(seen!<MapSite>(), isA<MapSite>());
  });

  test(
    'entries with other parameter names are a PageEntriesMismatchError',
    () async {
      final catalog = await startCatalog([
        mapModule([
          mapPage(
            '/p/:slug',
            sitemap: PageSitemap(
              entries: SitemapEntries.all(
                (_) async => [
                  const SitemapEntry(params: {'id': '1'}),
                ],
              ),
            ),
          ),
        ]),
      ]);

      await expectLater(
        catalog.sitemapOf<MapSite>().toList(),
        throwsA(isA<PageEntriesMismatchError>()),
      );
    },
  );

  test('the stream is lazy: nothing loads before it is listened to', () async {
    var loads = 0;
    final catalog = await startCatalog([
      mapModule([
        mapPage(
          '/p/:slug',
          sitemap: PageSitemap(
            entries: slugEntries(['a'], onLoad: (_) => loads++),
          ),
        ),
      ]),
    ]);

    catalog.sitemapOf<MapSite>();

    expect(loads, 0);
  });
}
