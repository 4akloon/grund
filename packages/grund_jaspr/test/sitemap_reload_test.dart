import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/sitemap_app.dart';
import 'helpers/sitemap_sites.dart';

void main() {
  test('a replaced snapshot is served, not the cached plan', () async {
    final first = await startSitemap([
      mapModule([mapPage('/a'), mapPage('/b')]),
    ]);
    final second = await startSitemap([
      mapModule([mapPage('/c')]),
    ]);
    final before = (await first.client.get('/sitemap.xml')).text;

    first.registry.replace(second.registry.current!);
    final response = await first.client.get('/sitemap.xml');

    expect(before, contains('https://x.test/b'));
    expect(response.status, 200);
    expect(response.text, contains('https://x.test/c'));
    expect(response.text, isNot(contains('https://x.test/a')));
  });

  test('a malformed chunk name never touches the source', () async {
    final source = RecordingEntries(5)..failure = StateError('down');
    final h = await startSitemap([
      mapModule([
        mapPage('/p/:slug', sitemap: PageSitemap(entries: source.entries)),
      ]),
    ]);

    for (final name in [
      'x.xml',
      '1',
      '0.xml',
      '01.xml',
      '+1.xml',
      '%201.xml',
      '1.xml.xml',
      '99999999999999999999.xml',
    ]) {
      expect((await h.client.get('/sitemap/$name')).status, 404, reason: name);
    }

    expect(source.counts, 0);
    expect(source.slices, isEmpty);
  });

  test('a page without addresses is never asked for a slice', () async {
    final empty = RecordingEntries(0);
    final h = await startSitemap([
      mapModule([
        mapPage('/a'),
        mapPage('/e/:slug', sitemap: PageSitemap(entries: empty.entries)),
        mapPage('/z'),
      ]),
    ]);

    final response = await h.client.get('/sitemap.xml');

    expect(response.status, 200);
    expect(empty.slices, isEmpty);
  });
}
