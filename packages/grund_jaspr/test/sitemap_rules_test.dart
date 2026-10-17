import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sites.dart';
import 'helpers/sitemap_sites.dart';

void main() {
  test('a guarded site with a sitemapBaseUrl is a GuardedSiteSitemapError', () {
    expect(
      startCatalog([
        CatalogPagesModule<GuardedMapSite>(GuardedMapSite.new, [
          markedPage('/'),
        ]),
      ]),
      throwsA(declaredError<GuardedSiteSitemapError>()),
    );
  });

  test('a parameterised page without entries is undecided', () {
    expect(
      startCatalog([
        mapModule([mapPage('/projects/:slug')]),
      ]),
      throwsA(declaredError<UndecidedPageSitemapError>()),
    );
  });

  test('a parameterised page with included false is decided', () async {
    final catalog = await startCatalog([
      mapModule([
        mapPage('/projects/:slug', sitemap: const PageSitemap(included: false)),
      ]),
    ]);

    expect(await catalog.sitemapOf<MapSite>().length, 1);
  });

  test('a parameterised page in a site without a sitemap is fine', () async {
    await startCatalog([
      CatalogPagesModule<PublicSite>(PublicSite.new, [
        markedPage('/'),
        markedPage('/projects/:slug'),
      ]),
    ]);
  });

  test('entries on a page without a parameter are unused', () {
    expect(
      startCatalog([
        mapModule([
          mapPage('/about', sitemap: PageSitemap(entries: slugEntries([]))),
        ]),
      ]),
      throwsA(declaredError<UnusedPageEntriesError>()),
    );
  });

  test('the page /sitemap.xml is reserved', () {
    expect(
      startCatalog([
        mapModule([mapPage('/sitemap.xml')]),
      ]),
      throwsA(declaredError<ReservedPagePathError>()),
    );
  });

  test('a page under /sitemap/ is reserved', () {
    expect(
      startCatalog([
        mapModule([mapPage('/sitemap/1.xml')]),
      ]),
      throwsA(declaredError<ReservedPagePathError>()),
    );
  });

  test('the sitemap path of a prefixed site is reserved', () {
    expect(
      startCatalog([
        CatalogPagesModule<DocsMapSite>(DocsMapSite.new, [
          mapPage('/'),
          mapPage('/sitemap.xml'),
        ]),
      ]),
      throwsA(declaredError<ReservedPagePathError>()),
    );
  });

  test('the sitemap path is reserved in a site without a sitemap', () {
    expect(
      startCatalog([
        CatalogPagesModule<PublicSite>(PublicSite.new, [
          markedPage('/'),
          markedPage('/sitemap.xml'),
        ]),
      ]),
      throwsA(declaredError<ReservedPagePathError>()),
    );
  });

  test('a page named /sitemap is not reserved', () async {
    await startCatalog([
      mapModule([mapPage('/sitemap')]),
    ]);
  });

  test('the errors name the path or type', () {
    expect(
      const UndecidedPageSitemapError('/p/:x').message,
      allOf(contains('/p/:x'), contains('included: false')),
    );
    expect(const UnusedPageEntriesError('/about').message, contains('/about'));
    expect(const GuardedSiteSitemapError(MapSite).message, contains('MapSite'));
    final mismatch = const PageEntriesMismatchError(
      path: '/p/:x',
      expected: ['x'],
      actual: ['y'],
    ).message;
    expect(mismatch, allOf(contains('/p/:x'), contains('x'), contains('y')));
  });
}
