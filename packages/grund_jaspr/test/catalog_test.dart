import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/site/page_registry.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sites.dart';
import 'helpers/validation_sites.dart';

List<String> _paths(List<SitePage> pages) => [
  for (final page in pages) page.path,
];

CatalogPagesModule<PublicSite> _publicWith(List<Page> pages) =>
    CatalogPagesModule<PublicSite>(PublicSite.new, pages);

void main() {
  group('PageCatalog', () {
    test('throws before the application prepared its runners', () {
      final catalog = PageCatalog(PageRegistry(), const JasprConfig());

      expect(
        catalog.pagesOf<PublicSite>,
        throwsA(isA<PageCatalogNotReadyError>()),
      );
      expect(
        catalog.navOf<PublicSite>,
        throwsA(isA<PageCatalogNotReadyError>()),
      );
      expect(
        () => catalog.match(Uri.parse('/')),
        throwsA(isA<PageCatalogNotReadyError>()),
      );
      expect(
        catalog.pagesWith<MarkdownLike>,
        throwsA(isA<PageCatalogNotReadyError>()),
      );
    });

    test(
      'pagesOf returns the pages of the exact site, sorted by path',
      () async {
        final catalog = await startCatalog(sampleSiteModules());

        expect(_paths(catalog.pagesOf<PublicSite>()), [
          '/',
          '/about',
          '/blog',
          '/contact',
          '/projects/:slug',
          '/projects/new',
        ]);
      },
    );

    test(
      'pagesOf<AdminSite> has no public and no SuperAdminSite pages',
      () async {
        final catalog = await startCatalog(sampleSiteModules());

        expect(_paths(catalog.pagesOf<AdminSite>()), [
          '/admin',
          '/admin/users/:id',
        ]);
        expect(_paths(catalog.pagesOf<SuperAdminSite>()), ['/super']);
      },
    );

    test('pagesOf of a site type nobody declared is empty', () async {
      final catalog = await startCatalog(sampleSiteModules());

      expect(catalog.pagesOf<BlogSite>(), isEmpty);
    });

    test('navOf orders by order, then label', () async {
      final catalog = await startCatalog(sampleSiteModules());

      final items = catalog.navOf<PublicSite>();

      expect(
        [for (final item in items) item.label],
        ['Articles', 'Home', 'About'],
      );
      expect(items.first.path, '/blog');
      expect(items.first.group, 'main');
    });

    test('navOf leaves out a page without nav', () async {
      final catalog = await startCatalog(sampleSiteModules());

      expect(
        catalog.navOf<PublicSite>().map((item) => item.path),
        isNot(contains('/contact')),
      );
    });

    test('navOf breaks a tie of order and label by path', () async {
      final catalog = await startCatalog([
        _publicWith([
          navPage('/', title: 'Home', nav: const PageNav()),
          navPage('/b', title: 'Same', nav: const PageNav()),
          navPage('/a', title: 'Same', nav: const PageNav()),
        ]),
      ]);

      expect(catalog.navOf<PublicSite>().map((item) => item.path), [
        '/',
        '/a',
        '/b',
      ]);
    });

    test('navOf uses the title when the nav has no label', () async {
      final catalog = await startCatalog(sampleSiteModules());

      expect(catalog.navOf<AdminSite>().single.label, 'Dashboard');
    });

    test('navOf leaves out a page with a :param in its path', () async {
      final catalog = await startCatalog([
        _publicWith([
          navPage('/', nav: const PageNav(label: 'Home')),
          navPage('/p/:slug', nav: const PageNav(label: 'Project')),
        ]),
      ]);

      expect(catalog.navOf<PublicSite>().map((item) => item.label), ['Home']);
    });

    test('navOf leaves out a page with its own hooks.use', () async {
      final catalog = await startCatalog([
        _publicWith([
          navPage('/', nav: const PageNav(label: 'Home')),
          markedPage(
            '/private',
            meta: const PageMeta(nav: PageNav(label: 'Private')),
            hooks: const PageHooks(use: [HookRef<CurrentUserHook>.type()]),
          ),
        ]),
      ]);

      expect(catalog.navOf<PublicSite>().map((item) => item.label), ['Home']);
    });

    test('navOf keeps a page with hooks.use and included: true', () async {
      final catalog = await startCatalog([
        _publicWith([
          navPage('/', nav: const PageNav(label: 'Home')),
          markedPage(
            '/private',
            meta: const PageMeta(
              nav: PageNav(label: 'Private'),
              sitemap: PageSitemap(included: true),
            ),
            hooks: const PageHooks(use: [HookRef<CurrentUserHook>.type()]),
          ),
        ]),
      ]);

      expect(catalog.navOf<PublicSite>().map((item) => item.label), [
        'Home',
        'Private',
      ]);
    });

    test('navOf leaves out a page with included: false', () async {
      final catalog = await startCatalog([
        _publicWith([
          navPage('/', nav: const PageNav(label: 'Home')),
          markedPage(
            '/hidden',
            meta: const PageMeta(
              nav: PageNav(label: 'Hidden'),
              sitemap: PageSitemap(included: false),
            ),
          ),
        ]),
      ]);

      expect(catalog.navOf<PublicSite>().map((item) => item.label), ['Home']);
    });

    test('pagesWith returns only the pages with that extension', () async {
      final catalog = await startCatalog([
        _publicWith([
          markedPage('/', extensions: const [OtherExtension()]),
          markedPage('/doc', extensions: const [MarkdownLike()]),
          markedPage('/plain'),
        ]),
      ]);

      expect(_paths(catalog.pagesWith<MarkdownLike>()), ['/doc']);
    });

    test(
      'match treats trailing-slash static and root file URLs as files',
      () async {
        final catalog = await startCatalog([
          _publicWith([markedPage('/'), markedPage('/:a')]),
        ], config: const JasprConfig(rootFiles: ['robots.txt', 'LICENSE']));

        for (final url in [
          '/static/x.css',
          '/robots.txt/',
          '/LICENSE',
          '/LICENSE/',
        ]) {
          expect(catalog.match(Uri.parse('http://x$url')), isNull, reason: url);
        }
        for (final url in ['/static', '/static/']) {
          expect(catalog.match(Uri.parse('http://x$url'))!.page.path, '/:a');
        }
      },
    );

    test('follows a replaced snapshot', () async {
      final first = await startCatalogApp([
        _publicWith([markedPage('/'), markedPage('/old')]),
      ]);
      final second = await startCatalogApp([
        _publicWith([markedPage('/'), markedPage('/new')]),
      ]);
      final catalog = first.injector<PageCatalog>();
      expect(catalog.match(Uri.parse('http://x/old')), isNotNull);
      expect(_paths(catalog.pagesOf<PublicSite>()), ['/', '/old']);

      first.injector<PageRegistry>().replace(
        second.injector<PageRegistry>().current!,
      );

      expect(catalog.match(Uri.parse('http://x/old')), isNull);
      expect(catalog.match(Uri.parse('http://x/new')), isNotNull);
      expect(_paths(catalog.pagesOf<PublicSite>()), ['/', '/new']);
    });

    test(
      'reads the pages the snapshot stored, never declaring again',
      () async {
        var declared = 0;
        final app = await startCatalogApp([
          CatalogPagesModule<PublicSite>(PublicSite.new, [
            navPage('/', nav: const PageNav(label: 'Home')),
          ], onDeclare: () => declared++),
        ]);
        final catalog = app.injector<PageCatalog>();
        declared = 0;

        catalog.pagesOf<PublicSite>();
        catalog.navOf<PublicSite>();
        catalog.pagesWith<MarkdownLike>();
        catalog.match(Uri.parse('http://x/'));

        expect(declared, 0);
      },
    );

    test('is exported by JasprModule', () async {
      final app = await startCatalogApp(sampleSiteModules());

      expect(app.injector<PageCatalog>(), isA<PageCatalog>());
    });
  });
}
