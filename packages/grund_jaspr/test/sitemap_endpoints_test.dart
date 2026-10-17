import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sitemap_app.dart';
import 'helpers/sitemap_sites.dart';
import 'helpers/sites.dart';

int _count(String body, String tag) => '<$tag>'.allMatches(body).length;

List<Page> _projects(RecordingEntries source) => [
  mapPage('/p/:slug', sitemap: PageSitemap(entries: source.entries)),
];

void main() {
  const config = JasprConfig(sitemapChunkSize: 3);

  test('no addresses give a urlset without url', () async {
    final h = await startSitemap([
      CatalogPagesModule<MapSite>(MapSite.new, [
        mapPage('/', sitemap: const PageSitemap(included: false)),
      ]),
    ]);

    final response = await h.client.get('/sitemap.xml');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'application/xml; charset=utf-8');
    expect(response.text, contains('<urlset'));
    expect(response.text, isNot(contains('<url>')));
  });

  test('exactly the chunk size is one file', () async {
    final source = RecordingEntries(2);
    final h = await startSitemap([
      mapModule(_projects(source)),
    ], config: config);

    final body = (await h.client.get('/sitemap.xml')).text;

    expect(body, contains('<urlset'));
    expect(_count(body, 'url'), 3);
  });

  test('one more address makes /sitemap.xml an index of two files', () async {
    final source = RecordingEntries(3);
    final h = await startSitemap([
      mapModule(_projects(source)),
    ], config: config);

    final index = (await h.client.get('/sitemap.xml')).text;
    final first = (await h.client.get('/sitemap/1.xml')).text;
    final second = (await h.client.get('/sitemap/2.xml')).text;

    expect(index, contains('<sitemapindex'));
    expect(_count(index, 'sitemap'), 2);
    expect(index, contains('<loc>https://x.test/sitemap/1.xml</loc>'));
    expect(index, contains('<loc>https://x.test/sitemap/2.xml</loc>'));
    expect(_count(first, 'url'), 3);
    expect(_count(second, 'url'), 1);
    expect(second, contains('https://x.test/p/s2'));
  });

  test('a bad or out-of-range chunk is 404', () async {
    final source = RecordingEntries(3);
    final h = await startSitemap([
      mapModule(_projects(source)),
    ], config: config);

    for (final name in [
      '3.xml',
      'x.xml',
      '0.xml',
      '1',
      '1.xml.xml',
      '-1.xml',
    ]) {
      expect((await h.client.get('/sitemap/$name')).status, 404, reason: name);
    }
  });

  test('HEAD /sitemap.xml is 200', () async {
    final h = await startSitemap([mapModule(const [])]);

    final response = await h.client.request('HEAD', '/sitemap.xml');

    expect(response.status, 200);
    expect(response.headers['content-type'], contains('application/xml'));
  });

  test('a site without sitemapBaseUrl has no sitemap route', () async {
    final h = await startSitemap([
      CatalogPagesModule<PublicSite>(PublicSite.new, [markedPage('/')]),
    ]);

    final response = await h.client.get('/sitemap.xml');

    expect(response.text, contains('public not found'));
  });

  test('a prefixed site serves under its path and indexes with it', () async {
    final source = RecordingEntries(4);
    final h = await startSitemap([
      CatalogPagesModule<DocsMapSite>(DocsMapSite.new, [
        mapPage('/'),
        mapPage('/p/:slug', sitemap: PageSitemap(entries: source.entries)),
      ]),
    ], config: config);

    final index = (await h.client.get('/docs/sitemap.xml')).text;
    final second = (await h.client.get('/docs/sitemap/2.xml')).text;

    expect(index, contains('<loc>https://x.test/docs/sitemap/1.xml</loc>'));
    expect(index, contains('<loc>https://x.test/docs/sitemap/2.xml</loc>'));
    expect(second, contains('https://x.test/docs/p/s2'));
    expect((await h.client.get('/sitemap.xml')).status, 404);
  });

  test(
    'XML specials and Cyrillic in an entry are escaped and encoded',
    () async {
      final h = await startSitemap([
        mapModule([
          mapPage(
            '/p/:slug',
            sitemap: PageSitemap(entries: slugEntries(['a&b<c>', 'привіт'])),
          ),
        ]),
      ]);

      final body = (await h.client.get('/sitemap.xml')).text;

      expect(body, contains('https://x.test/p/a%26b%3Cc%3E'));
      expect(
        body,
        contains('https://x.test/p/%D0%BF%D1%80%D0%B8%D0%B2%D1%96%D1%82'),
      );
      expect(body, isNot(contains('a&b')));
    },
  );
}
