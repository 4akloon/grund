import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'helpers/alternate_sites.dart';
import 'helpers/catalog_app.dart';
import 'helpers/no_injector.dart';
import 'helpers/sites.dart';

Future<TestClient> _start(List<Module> modules) async =>
    TestClient.of(await startCatalogApp(modules));

PageMatch _matchOf(Page page, {String sitePath = '', Map<String, String>? p}) =>
    PageMatch(
      page: SitePage(
        site: sitePath.isEmpty
            ? PlainAltSite(const NoInjector())
            : DocsAltSite(const NoInjector()),
        page: page,
        path: sitePath + page.path,
      ),
      params: p ?? const {},
    );

void main() {
  group('own URLs', () {
    late TestClient client;
    setUp(() async => client = await _start([altModule(PlainAltSite.new)]));

    test('the root of a root site is /index.md', () async {
      final response = await client.get('/index.md');
      expect(response.status, 200);
      expect(response.text, '# home');
    });

    test('a page is served at its path plus the suffix', () async {
      expect((await client.get('/about.md')).text, '# about');
    });

    test('the builder gets the path parameters', () async {
      final response = await client.get('/projects/grund.md');
      expect(response.text, '# project grund');
    });

    test('the type is the media type in UTF-8', () async {
      final response = await client.get('/about.md');
      expect(response.headers['content-type'], 'text/markdown; charset=utf-8');
    });

    test('cache-control defaults to private, no-cache', () async {
      final response = await client.get('/about.md');
      expect(response.headers['cache-control'], 'private, no-cache');
    });

    test('there is no canonical link without a base URL', () async {
      expect((await client.get('/about.md')).headers.contains('link'), isFalse);
    });

    test('a trailing slash is redirected to the file spelling', () async {
      final response = await client.get('/about.md/');
      expect(response.status, 308);
      expect(response.headers['location'], '/about.md');
    });

    test('NotFoundException of the builder is a problem+json 404', () async {
      final response = await client.get('/projects/nope.md');
      expect(response.status, 404);
      expect(response.headers['content-type'], contains('problem+json'));
    });

    test('only GET is routed', () async {
      expect((await client.delete('/about.md')).status, 405);
    });
  });

  test('a builder may set its own cache-control', () async {
    final client = await _start([
      altModule(PlainAltSite.new, [
        Page(
          '/',
          alternates: [
            PageAlternate.markdown((c, m) {
              c.response.headers.set('cache-control', 'max-age=60');
              return '# x';
            }),
          ],
          build: (_) => const Component.text('x'),
        ),
      ]),
    ]);
    final response = await client.get('/index.md');
    expect(response.headers['cache-control'], 'max-age=60');
  });

  group('canonical link', () {
    test('points to the page with a base URL', () async {
      final client = await _start([altModule(BaseAltSite.new)]);
      final response = await client.get('/about.md');
      expect(response.headers.all('link'), [
        '<https://x.test/about>; rel="canonical"',
      ]);
    });

    test('follows the trailing slash policy', () async {
      final client = await _start([altModule(AlwaysAltSite.new)]);
      final response = await client.get('/about.md');
      expect(response.headers.all('link'), [
        '<https://x.test/about/>; rel="canonical"',
      ]);
    });

    test('x-robots-tag from the builder reaches the response', () async {
      final client = await _start([
        altModule(PlainAltSite.new, [
          Page(
            '/',
            alternates: [
              PageAlternate.markdown((c, m) {
                c.response.headers.set('x-robots-tag', 'noindex');
                return '# x';
              }),
            ],
            build: (_) => const Component.text('x'),
          ),
        ]),
      ]);
      expect(
        (await client.get('/index.md')).headers['x-robots-tag'],
        'noindex',
      );
    });
  });

  test('the root of a prefixed site is /docs/index.md', () async {
    final client = await _start([altModule(DocsAltSite.new)]);
    expect((await client.get('/docs/index.md')).text, '# home');
    expect((await client.get('/docs/about.md')).text, '# about');
  });

  group('hooks of alternates', () {
    late TestClient client;
    setUp(() async {
      client = await _start([
        altModule(GuardedAltSite.new, [
          markedPage('/'),
          Page(
            '/open',
            hooks: const PageHooks(skip: [AdminGuard]),
            alternates: [PageAlternate.markdown((c, m) => '# open')],
            build: (_) => const Component.text('open'),
          ),
          Page(
            '/own',
            hooks: const PageHooks(
              use: [HookRef<HeaderHook>.instance(HeaderHook())],
            ),
            alternates: [PageAlternate.markdown((c, m) => '# own')],
            build: (_) => const Component.text('own'),
          ),
          Page(
            '/closed',
            alternates: [PageAlternate.markdown((c, m) => '# closed')],
            build: (_) => const Component.text('closed'),
          ),
        ]),
      ]);
    });

    test('a guest is refused as on the page', () async {
      final page = await client.get('/admin/closed');
      final alternate = await client.get('/admin/closed.md');
      expect(page.status, 401);
      expect(alternate.status, page.status);
    });

    test('an admin gets the alternate', () async {
      final response = await client.get(
        '/admin/closed.md',
        headers: adminHeaders,
      );
      expect(response.text, '# closed');
    });

    test('skip applies to the alternate', () async {
      expect((await client.get('/admin/open.md')).text, '# open');
    });

    test('use applies to the alternate', () async {
      final response = await client.get('/admin/own.md', headers: adminHeaders);
      expect(response.headers.all('vary'), ['cookie']);
      expect(response.headers.all('link'), ['</hook>; rel="preload"']);
    });
  });

  test('the skip warning is logged once per page, not per route', () async {
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    addTearDown(() => Logger.root.level = previous);
    final records = <String>[];
    final sub = Logger('grund.jaspr').onRecord
        .listen((record) => records.add(record.message));
    addTearDown(sub.cancel);
    await _start([
      altModule(GuardedAltSite.new, [
        markedPage('/'),
        Page(
          '/open',
          hooks: const PageHooks(skip: [AdminGuard]),
          alternates: [
            PageAlternate.markdown((c, m) => '# a'),
            const PageAlternate(
              mediaType: 'text/plain',
              suffix: '.txt',
              build: _text,
            ),
          ],
          build: (_) => const Component.text('open'),
        ),
      ]),
    ]);
    expect(
      records.where((m) => m.contains('page /admin/open skips')),
      hasLength(1),
    );
  });

  group('PageMatch.alternatePath', () {
    final page = Page(
      '/projects/:slug',
      alternates: [PageAlternate.markdown((c, m) => '')],
      build: (_) => const Component.text(''),
    );

    test('adds the suffix to the path with its values', () {
      final match = _matchOf(page, p: {'slug': 'a b'});
      expect(match.alternatePath('text/markdown'), '/projects/a%20b.md');
    });

    test('knows the root of a prefixed site', () {
      final root = Page('/', alternates: page.alternates, build: page.build);
      expect(
        _matchOf(root, sitePath: '/docs').alternatePath('text/markdown'),
        '/docs/index.md',
      );
    });

    test('is null for a media type the page lacks', () {
      expect(
        _matchOf(page, p: {'slug': 'a'}).alternatePath('text/plain'),
        isNull,
      );
    });
  });
}

String _text(HttpCtx c, PageMatch match) => 'text';
