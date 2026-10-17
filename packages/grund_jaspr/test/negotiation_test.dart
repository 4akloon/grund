import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/alternate_sites.dart';
import 'helpers/catalog_app.dart';

const _config = JasprConfig();

Future<TestClient> _start(List<Module> modules) async =>
    TestClient.of(await startCatalogApp(modules, config: _config));

/// Accept header, whether Markdown is the answer (spec 4.7).
const _table = <(String?, bool)>[
  (null, false),
  ('', false),
  ('*/*', false),
  ('text/*', false),
  ('application/json', false),
  ('text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', false),
  (',,;;,q=', false),
  ('text/markdown;q=0', false),
  ('text/markdown;q=abc', false),
  ('text/markdown;q=0.5, text/html', false),
  ('text/markdown;q=0.1, */*', false),
  ('text/markdown', true),
  ('TEXT/MARKDOWN', true),
  ('text/markdown;charset=utf-8', true),
  ('text/markdown, text/html;q=0.9', true),
  ('text/html, text/markdown', true),
  ('text/markdown;q=0.5, */*;q=0.5', true),
];

void main() {
  late TestClient client;
  setUp(() async => client = await _start([altModule(PlainAltSite.new)]));

  group('Accept table', () {
    for (final (accept, markdown) in _table) {
      test('"$accept" gives ${markdown ? 'Markdown' : 'HTML'}', () async {
        final headers = {'accept': ?accept};
        final response = await client.get('/about', headers: headers);
        expect(response.status, 200);
        expect(
          response.headers['content-type'],
          markdown
              ? 'text/markdown; charset=utf-8'
              : 'text/html; charset=utf-8',
        );
        expect(response.text, markdown ? '# about' : contains('html about'));
        expect(response.headers.all('vary'), ['accept']);
      });
    }
  });

  test('HEAD with Accept: text/markdown has the headers of GET', () async {
    const headers = {'accept': 'text/markdown'};
    final get = await client.get('/about', headers: headers);
    final head = await client.head('/about', headers: headers);
    expect(head.status, get.status);
    expect(head.headers['content-type'], get.headers['content-type']);
    expect(head.headers['cache-control'], get.headers['cache-control']);
    expect(head.headers.all('vary'), ['accept']);
  });

  test('the HTML links to its alternates', () async {
    final response = await client.get('/about');
    expect(response.headers.all('link'), [
      '</about.md>; rel="alternate"; type="text/markdown"',
    ]);
  });

  test('the link of the root page is /index.md', () async {
    final response = await client.get('/');
    expect(response.headers.all('link'), [
      '</index.md>; rel="alternate"; type="text/markdown"',
    ]);
  });

  test('the link is absolute with a base URL', () async {
    final based = await _start([altModule(BaseAltSite.new)]);
    final response = await based.get('/about');
    expect(response.headers.all('link'), [
      '<https://x.test/about.md>; rel="alternate"; type="text/markdown"',
    ]);
  });

  test('the negotiated Markdown has no canonical link', () async {
    final based = await _start([altModule(BaseAltSite.new)]);
    final response = await based.get(
      '/about',
      headers: {'accept': 'text/markdown'},
    );
    expect(response.headers.all('link'), isEmpty);
  });

  test('a page without alternates has no vary and no link', () async {
    final plain = await _start([
      altModule(PlainAltSite.new, [
        Page('/', build: (_) => const Component.text('root')),
        Page('/plain', build: (_) => const Component.text('plain')),
      ]),
    ]);
    final response = await plain.get('/plain');
    expect(response.headers.contains('vary'), isFalse);
    expect(response.headers.contains('link'), isFalse);
  });

  test('a hook adds its vary token and link to the HTML', () async {
    final hooked = await _start([
      altModule(PlainAltSite.new, [
        Page('/', build: (_) => const Component.text('root')),
        Page(
          '/h',
          alternates: [PageAlternate.markdown((c, m) => '# h')],
          hooks: const PageHooks(
            use: [HookRef<HeaderHook>.instance(HeaderHook())],
          ),
          build: (_) => const Component.text('h'),
        ),
      ]),
    ]);
    final response = await hooked.get('/h');
    expect(response.headers.all('vary'), ['accept, cookie']);
    expect(response.headers.all('link'), [
      '</hook>; rel="preload"',
      '</h.md>; rel="alternate"; type="text/markdown"',
    ]);
  });

  test(
    'an alternate that throws NotFoundException gives the 404 page',
    () async {
      final response = await client.get(
        '/projects/nope',
        headers: {'accept': 'text/markdown'},
      );
      expect(response.status, 404);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.text, contains('Not found'));
      expect(response.headers.all('vary'), ['accept']);
      expect(response.headers.contains('link'), isFalse);
    },
  );

  test('a 404 page of HTML has vary but no alternate link', () async {
    final response = await client.get('/projects/nope');
    expect(response.status, 404);
    expect(response.headers.all('vary'), ['accept']);
    expect(response.headers.contains('link'), isFalse);
  });

  test('a redirect carries no vary', () async {
    final response = await client.get('/about/');
    expect(response.status, 308);
    expect(response.headers.contains('vary'), isFalse);
  });

  test('the Markdown of a parameterised page gets the slug', () async {
    final response = await client.get(
      '/projects/grund',
      headers: {'accept': 'text/markdown'},
    );
    expect(response.text, '# project grund');
  });

  group('two alternates', () {
    late TestClient two;
    setUp(() async {
      two = await _start([
        altModule(PlainAltSite.new, [
          Page(
            '/',
            alternates: [
              PageAlternate.markdown((c, m) => '# md'),
              PageAlternate(
                mediaType: 'text/plain',
                suffix: '.txt',
                build: (c, m) => 'plain',
              ),
            ],
            build: (_) => const Component.text('root'),
          ),
        ]),
      ]);
    });

    Future<String> bodyFor(String accept) async =>
        (await two.get('/', headers: {'accept': accept})).text;

    test('the higher quality wins', () async {
      expect(await bodyFor('text/markdown;q=0.5, text/plain'), 'plain');
    });

    test('the first declared wins a tie', () async {
      expect(await bodyFor('text/plain, text/markdown'), '# md');
    });
  });
}
