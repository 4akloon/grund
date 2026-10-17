import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/alternate_sites.dart';
import 'helpers/catalog_app.dart';

String _build(HttpCtx c, PageMatch match) => '';

Component _html(HttpCtx c) => const Component.text('x');

Future<void> _start(
  List<PageAlternate> alternates, {
  JasprConfig config = const JasprConfig(),
  String path = '/about',
}) async {
  await startCatalogApp([
    altModule(PlainAltSite.new, [
      Page('/', build: _html),
      Page(path, alternates: alternates, build: _html),
    ]),
  ], config: config);
}

PageAlternate _alt(String mediaType, String suffix) =>
    PageAlternate(mediaType: mediaType, suffix: suffix, build: _build);

Matcher _invalid(String mediaType, String reason) => throwsA(
  isA<InvalidPageAlternateError>()
      .having((e) => e.mediaType, 'mediaType', mediaType)
      .having((e) => e.reason, 'reason', contains(reason)),
);

void main() {
  group('InvalidPageAlternateError', () {
    final cases = <(String, PageAlternate, String)>[
      ('upper case type', _alt('text/HTML', '.x'), 'lower case'),
      ('parameters', _alt('text/markdown; x=1', '.x'), 'no parameters'),
      ('wildcard subtype', _alt('text/*', '.x'), 'no wildcards'),
      ('the page itself', _alt('text/html', '.x'), 'the page itself'),
      ('no type/subtype', _alt('markdown', '.x'), 'lower case'),
      ('suffix without dot', _alt('text/markdown', 'md'), 'suffix'),
      ('upper case suffix', _alt('text/markdown', '.MD'), 'suffix'),
      ('trailing dot', _alt('text/markdown', '.md.'), 'suffix'),
      ('page suffix', _alt('text/markdown', '.html'), 'pageSuffixes'),
      (
        'page suffix after a dot',
        _alt('text/markdown', '.tar.xml'),
        'pageSuffixes',
      ),
    ];
    for (final (name, alternate, reason) in cases) {
      test(
        name,
        () => expectLater(
          _start([alternate]),
          _invalid(alternate.mediaType, reason),
        ),
      );
    }

    test('a repeated type', () async {
      await expectLater(
        _start([_alt('text/markdown', '.md'), _alt('text/markdown', '.mdx')]),
        _invalid('text/markdown', 'already has an alternate of this type'),
      );
    });

    test('a repeated suffix', () async {
      await expectLater(
        _start([_alt('text/markdown', '.md'), _alt('text/plain', '.md')]),
        _invalid('text/plain', 'already has an alternate with the suffix'),
      );
    });

    test('a URL under the static path', () async {
      await expectLater(
        _start([
          _alt('text/markdown', '.md'),
        ], config: const JasprConfig(staticPath: '/about.md')),
        _invalid('text/markdown', 'static files'),
      );
    });

    test('a root file URL', () async {
      await expectLater(
        _start(
          [_alt('text/plain', '.txt')],
          config: const JasprConfig(rootFiles: ['robots.txt']),
          path: '/robots',
        ),
        _invalid('text/plain', 'robots.txt'),
      );
    });

    test('the sitemap URL', () async {
      await expectLater(
        _start(
          [_alt('application/xml', '.xml')],
          config: const JasprConfig(pageSuffixes: ['html']),
          path: '/sitemap',
        ),
        _invalid('application/xml', 'sitemap'),
      );
    });
  });

  group('requiredAlternates', () {
    test('a page without the required alternate fails at startup', () async {
      await expectLater(
        startCatalogApp([
          altModule(RequiringAltSite.new, [Page('/', build: _html)]),
        ]),
        throwsA(
          isA<MissingPageAlternateError>()
              .having((e) => e.path, 'path', '/')
              .having((e) => e.mediaType, 'mediaType', 'text/markdown'),
        ),
      );
    });

    test('pages with the alternate start', () async {
      await startCatalogApp([altModule(RequiringAltSite.new)]);
    });
  });

  test('a page cannot declare a suffix in a parameter name', () async {
    await expectLater(
      _start([], path: '/:slug.md'),
      throwsA(isA<InvalidPagePathError>()),
    );
  });

  test('pages /index and / with Markdown collide on /index.md', () async {
    await expectLater(
      startCatalogApp([
        altModule(PlainAltSite.new, [
          Page('/', alternates: [PageAlternate.markdown(_build)], build: _html),
          Page(
            '/index',
            alternates: [PageAlternate.markdown(_build)],
            build: _html,
          ),
        ]),
      ]),
      throwsA(isA<DuplicateRouteError>()),
    );
  });
}
