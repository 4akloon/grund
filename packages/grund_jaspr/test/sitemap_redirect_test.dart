import 'package:grund/grund.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sitemap_sites.dart';
import 'helpers/slash_sites.dart';

Future<TestClient> _start(Module module) async =>
    TestClient.of(await startCatalogApp([module]));

void main() {
  test('/sitemap.xml/ redirects to /sitemap.xml', () async {
    final client = await _start(mapModule([]));

    final response = await client.get('/sitemap.xml/');

    expect(response.status, 308);
    expect(response.headers['location'], '/sitemap.xml');
  });

  test('/sitemap/1/ redirects to /sitemap/1', () async {
    final client = await _start(mapModule([]));

    final response = await client.get('/sitemap/1/');

    expect(response.status, 308);
    expect(response.headers['location'], '/sitemap/1');
  });

  test('the sitemap of a prefixed site redirects within the prefix', () async {
    final client = await _start(
      CatalogPagesModule<DocsMapSite>(DocsMapSite.new, [mapPage('/')]),
    );

    final response = await client.get('/docs/sitemap.xml/');

    expect(response.status, 308);
    expect(response.headers['location'], '/docs/sitemap.xml');
  });

  test('under always the sitemap files get no slash', () async {
    final client = await _start(
      CatalogPagesModule<AlwaysSite>(AlwaysSite.new, [mapPage('/')]),
    );

    expect((await client.get('/sitemap.xml')).status, 200);
  });
}
