import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/file_sites.dart';
import 'helpers/sites.dart';
import 'helpers/validation_sites.dart';

Module _root(List<SiteFile> files, {bool withBaseUrl = false}) =>
    SiteWithPagesModule<FilesSite>(
      (i) => FilesSite(i, files, withBaseUrl: withBaseUrl),
    );

Future<TestClient> _start(List<Module> modules) async =>
    TestClient.of(await startCatalogApp(modules));

void main() {
  group('serving', () {
    test('a root site serves /robots.txt as UTF-8 text', () async {
      final client = await _start([
        _root([textFile('/robots.txt', text: 'User-agent: *')]),
      ]);

      final response = await client.get('/robots.txt');

      expect(response.status, 200);
      expect(response.text, 'User-agent: *');
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
    });

    test('the media type is the one declared', () async {
      final client = await _start([
        _root([textFile('/google1.html', mediaType: 'text/html')]),
      ]);

      final response = await client.get('/google1.html');

      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });

    test('a prefixed site serves its file under the prefix', () async {
      final client = await _start([
        SiteWithPagesModule<DocsFilesSite>(
          (i) => DocsFilesSite(i, [textFile('/llms.txt')]),
        ),
      ]);

      expect((await client.get('/docs/llms.txt')).text, 'body of /llms.txt');
      expect((await client.get('/llms.txt')).status, 404);
    });

    test('caching defaults to private, no-cache', () async {
      final client = await _start([
        _root([textFile('/robots.txt')]),
      ]);

      final response = await client.get('/robots.txt');

      expect(response.headers['cache-control'], 'private, no-cache');
    });

    test('a cache-control set through c.response is kept', () async {
      final client = await _start([
        _root([
          SiteFile(
            '/robots.txt',
            mediaType: 'text/plain',
            build: (c) {
              c.response.headers.set('cache-control', 'max-age=60');
              return 'x';
            },
          ),
        ]),
      ]);

      final response = await client.get('/robots.txt');

      expect(response.headers['cache-control'], 'max-age=60');
    });

    test('HEAD answers 200 with the same content-type', () async {
      final client = await _start([
        _root([textFile('/robots.txt')]),
      ]);

      final response = await client.head('/robots.txt');

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
    });

    test('the builder gets the request context', () async {
      final client = await _start([
        _root([
          SiteFile(
            '/who.txt',
            mediaType: 'text/plain',
            build: (c) => c.query.string('n'),
          ),
        ]),
      ]);

      expect((await client.get('/who.txt?n=7')).text, '7');
    });
  });

  group('addresses', () {
    test('/robots.txt/ redirects to /robots.txt', () async {
      final client = await _start([
        _root([textFile('/robots.txt')]),
      ]);

      final response = await client.get('/robots.txt/');

      expect(response.status, 308);
      expect(response.headers['location'], '/robots.txt');
      expect(response.headers['cache-control'], 'max-age=3600');
    });

    test('a file is not redirected under always', () async {
      final client = await _start([
        SiteWithPagesModule<_AlwaysFilesSite>(
          (i) => _AlwaysFilesSite(i, [textFile('/robots.txt')]),
        ),
      ]);

      expect((await client.get('/robots.txt')).status, 200);
      final slash = await client.get('/robots.txt/');
      expect(slash.status, 308);
      expect(slash.headers['location'], '/robots.txt');
    });
  });

  group('hooks', () {
    late TestClient client;
    setUp(() async {
      client = await _start([
        SiteWithPagesModule<AdminFilesSite>(
          (i) => AdminFilesSite(i, [textFile('/x.txt')]),
        ),
      ]);
    });

    test('the hooks of the site guard a file', () async {
      expect((await client.get('/admin/x.txt')).status, 401);
    });

    test('a file passes the hooks of the site', () async {
      final response = await client.get('/admin/x.txt', headers: adminHeaders);

      expect(response.status, 200);
    });
  });

  group('territory', () {
    test('a file of the root site under another site is rejected', () {
      expect(
        startCatalogApp([
          SiteWithPagesModule<FilesSite>(
            (i) => FilesSite(i, [textFile('/admin/x.txt')]),
          ),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
        ]),
        throwsA(
          isA<MisplacedPagePathError>().having(
            (e) => e.path,
            'path',
            '/admin/x.txt',
          ),
        ),
      );
    });

    test('the message names a file', () {
      expect(
        startCatalogApp([
          SiteWithPagesModule<FilesSite>(
            (i) => FilesSite(i, [textFile('/admin/x.txt')]),
          ),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
        ]),
        throwsA(
          isA<MisplacedPagePathError>().having(
            (e) => e.message,
            'message',
            contains('The page or file "/admin/x.txt"'),
          ),
        ),
      );
    });

    test('the same file in the owning site is accepted', () async {
      final client = await _start([
        SiteWithPagesModule<AdminFilesSite>(
          (i) => AdminFilesSite(i, [textFile('/x.txt')]),
        ),
      ]);

      expect(
        (await client.get('/admin/x.txt', headers: adminHeaders)).status,
        200,
      );
    });
  });

  group('declaration', () {
    Matcher invalid(String path, String reason) => throwsA(
      isA<InvalidSiteFileError>()
          .having((e) => e.path, 'path', path)
          .having((e) => e.reason, 'reason', contains(reason)),
    );

    final cases = <(String, SiteFile, String)>[
      ('no leading slash', textFile('robots.txt'), 'start with'),
      ('the root', textFile('/'), 'name a file'),
      ('a parameter', textFile('/a/:x'), 'literal'),
      ('a wildcard', textFile('/a/*'), 'literal'),
      ('an empty segment', textFile('/a//b'), 'empty'),
      ('the static path', textFile('/static/x.txt'), 'static'),
      ('the sitemap', textFile('/sitemap.xml'), 'sitemap'),
      ('a query', textFile('/a.txt?x=1'), 'dot segment'),
      ('a fragment', textFile('/a#x'), 'dot segment'),
      ('a percent escape', textFile('/a%2Fb.txt'), 'dot segment'),
      ('a parent segment', textFile('/a/../b.txt'), 'dot segment'),
      ('a current segment', textFile('/./b.txt'), 'dot segment'),
      ('a sitemap chunk', textFile('/sitemap/1'), 'sitemap'),
      (
        'a media type without a subtype',
        textFile('/a', mediaType: 'text'),
        'type/subtype',
      ),
    ];
    for (final (name, file, reason) in cases) {
      test('$name is rejected', () {
        expect(
          startCatalogApp([
            _root([file], withBaseUrl: true),
          ]),
          invalid(file.path, reason),
        );
      });
    }

    test('a file on the own URL of an alternate is a duplicate route', () {
      expect(
        startCatalogApp([
          CatalogPagesModule<FilesSite>(
            (i) => FilesSite(i, [textFile('/about.md')]),
            [
              markedPage('/'),
              Page(
                '/about',
                alternates: [PageAlternate.markdown((c, m) => '#')],
                build: (_) => const Component.text('x'),
              ),
            ],
          ),
        ]),
        throwsA(isA<DuplicateRouteError>()),
      );
    });

    test('a path declared twice is a duplicate route', () {
      expect(
        startCatalogApp([
          _root([textFile('/a.txt'), textFile('/a.txt')]),
        ]),
        throwsA(isA<DuplicateRouteError>()),
      );
    });
  });
}

final class _AlwaysFilesSite extends FilesSite {
  _AlwaysFilesSite(super.injector, super.files);

  @override
  TrailingSlash get trailingSlash => TrailingSlash.always;
}
