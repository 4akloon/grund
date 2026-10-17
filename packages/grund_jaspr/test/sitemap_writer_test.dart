import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/sitemap/sitemap_writer.dart';
import 'package:test/test.dart';

void main() {
  const namespace = 'http://www.sitemaps.org/schemas/sitemap/0.9';

  test('urlSet has the declaration and the namespace', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse('https://x.test/a')),
    ]);

    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('<urlset xmlns="$namespace">'));
    expect(xml, contains('<loc>https://x.test/a</loc>'));
  });

  test('an empty urlSet is a valid empty element', () {
    expect(SitemapWriter.urlSet(const []), contains('<urlset'));
    expect(SitemapWriter.urlSet(const []), isNot(contains('<url>')));
  });

  test('ampersands in the location are escaped', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse('https://x.test/a?b=1&c=2')),
    ]);

    expect(xml, contains('<loc>https://x.test/a?b=1&amp;c=2</loc>'));
  });

  test('the five XML characters are escaped in the location', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse("https://x.test/a?q=<'\">&")),
    ]);

    final loc = RegExp('<loc>(.*)</loc>').firstMatch(xml)!.group(1)!;

    expect(loc, isNot(anyOf(contains('<'), contains('>'), contains('"'))));
    expect(loc, contains('&apos;'));
    expect(loc, contains('&amp;'));
    expect(loc, isNot(contains("'")));
  });

  test('a raw apostrophe and ampersand in the location are escaped', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse("https://x.test/a'b?c=1&d=2")),
    ]);

    expect(xml, contains('<loc>https://x.test/a&apos;b?c=1&amp;d=2</loc>'));
  });

  test('Cyrillic segments are percent-encoded', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse('https://x.test/проєкти/п')),
    ]);

    expect(xml, contains('/%D0%BF%D1%80%D0%BE%D1%94%D0%BA%D1%82%D0%B8/%D0%BF'));
  });

  test('optional fields are written in the protocol form', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(
        location: Uri.parse('https://x.test/a'),
        lastModified: DateTime.utc(2026, 1, 2, 3, 4, 5),
        changeFrequency: SitemapChangeFrequency.weekly,
        priority: 0.5,
      ),
    ]);

    expect(xml, contains('<lastmod>2026-01-02T03:04:05.000Z</lastmod>'));
    expect(xml, contains('<changefreq>weekly</changefreq>'));
    expect(xml, contains('<priority>0.5</priority>'));
  });

  test('a local lastModified is written in UTC', () {
    final local = DateTime(2026, 6, 1, 12);
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse('https://x.test/a'), lastModified: local),
    ]);

    expect(
      xml,
      contains('<lastmod>${local.toUtc().toIso8601String()}</lastmod>'),
    );
  });

  test('a priority has exactly one decimal digit', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse('https://x.test/a'), priority: 1),
      SitemapUrl(location: Uri.parse('https://x.test/b'), priority: 0.25),
    ]);

    expect(xml, contains('<priority>1.0</priority>'));
    expect(xml, contains('<priority>0.3</priority>'));
  });

  test('absent fields write no elements', () {
    final xml = SitemapWriter.urlSet([
      SitemapUrl(location: Uri.parse('https://x.test/a')),
    ]);

    expect(xml, isNot(contains('lastmod')));
    expect(xml, isNot(contains('changefreq')));
    expect(xml, isNot(contains('priority')));
  });

  test('index lists every file', () {
    final xml = SitemapWriter.index([
      Uri.parse('https://x.test/sitemap/0.xml'),
      Uri.parse('https://x.test/sitemap/1.xml'),
    ]);

    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('<sitemapindex xmlns="$namespace">'));
    expect(xml, contains('<loc>https://x.test/sitemap/0.xml</loc>'));
    expect(xml, contains('<loc>https://x.test/sitemap/1.xml</loc>'));
    expect('<sitemap>'.allMatches(xml), hasLength(2));
  });
}
