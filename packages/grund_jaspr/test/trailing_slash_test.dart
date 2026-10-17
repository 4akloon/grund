import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/site/canonical_redirect.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sites.dart';
import 'helpers/slash_sites.dart';

const _config = JasprConfig(pageSuffixes: ['html', 'xml']);

Future<TestClient> _start(Module module) async =>
    TestClient.of(await startCatalogApp([module], config: _config));

void main() {
  group('never', () {
    late TestClient client;
    setUp(() async => client = await _start(slashModule(NeverSite.new, [])));

    test('redirects a trailing slash with 308', () async {
      final response = await client.get('/about/');
      expect(response.status, 308);
      expect(response.headers['location'], '/about');
      expect(response.headers['cache-control'], 'max-age=3600');
    });

    test('keeps the query verbatim', () async {
      final response = await client.get('/about/?x=1&y');
      expect(response.headers['location'], '/about?x=1&y');
    });

    test('drops an empty segment', () async {
      final response = await client.get('/about//');
      expect(response.headers['location'], '/about');
    });

    test('serves the root and the canonical spelling', () async {
      expect((await client.get('/')).status, 200);
      expect((await client.get('/about')).status, 200);
    });

    test('a HEAD request is redirected too', () async {
      final response = await client.head('/about/');
      expect(response.status, 308);
      expect(response.headers['location'], '/about');
    });

    test('keeps %2F inside a segment', () async {
      final response = await client.get('/projects/a%2Fb/');
      expect(response.status, 308);
      expect(response.headers['location'], '/projects/a%2Fb');
    });

    test('the fallback answers 404 without a redirect', () async {
      expect((await client.get('/nope/')).status, 404);
    });

    test('the fallback answers 404 for a slash after a file name', () async {
      final response = await client.get('/logo.png/');
      expect(response.status, 404);
      expect(response.headers['location'], isNull);
    });

    test('a file request on a page route is file_not_found', () async {
      final response = await client.get('/projects/logo.png');
      expect(response.status, 404);
      expect(response.headers['location'], isNull);
      expect(response.text, contains('file_not_found'));
    });

    test('a file request is answered before the redirect', () async {
      final response = await client.get('/projects//logo.png');
      expect(response.status, 404);
      expect(response.headers['location'], isNull);
    });

    test('a slash after a file name redirects, then it is a 404', () async {
      final response = await client.get('/projects/logo.png/');
      expect(response.status, 308);
      expect(response.headers['location'], '/projects/logo.png');
    });
  });

  group('CanonicalRedirect on a raw path', () {
    String? location(String path, TrailingSlash policy) =>
        CanonicalRedirect.forPage(
          Uri.parse('http://h$path'),
          policy,
        )?.headers['location'];

    test('a leading empty segment is dropped', () {
      expect(location('//about', TrailingSlash.never), '/about');
    });

    test('a foreign host in the first segment stays a path', () {
      expect(
        location('//evil.test/about/', TrailingSlash.never),
        '/evil.test/about',
      );
      expect(location('///evil.test/x', TrailingSlash.always), '/evil.test/x/');
    });

    test('only empty segments make the root', () {
      expect(location('//', TrailingSlash.never), '/');
    });

    test('a file is never given a slash', () {
      expect(
        CanonicalRedirect.forFile(
          Uri.parse('http://h/a.md/'),
          TrailingSlash.always,
        )?.headers['location'],
        '/a.md',
      );
    });
  });

  test('the root of a prefixed site redirects to the prefix', () async {
    final client = await _start(slashModule(DocsNeverSite.new, []));

    final response = await client.get('/docs/');

    expect(response.status, 308);
    expect(response.headers['location'], '/docs');
  });

  group('always', () {
    late TestClient client;
    late List<String> builds;
    setUp(() async {
      builds = [];
      client = await _start(slashModule(AlwaysSite.new, builds));
    });

    test('adds the slash', () async {
      final response = await client.get('/about');
      expect(response.status, 308);
      expect(response.headers['location'], '/about/');
    });

    test('redirects before the builder runs', () async {
      final response = await client.get('/projects/grund');
      expect(response.headers['location'], '/projects/grund/');
      expect(builds, isEmpty);
    });

    test('leaves a file-like last segment alone', () async {
      expect((await client.get('/feed.xml')).status, 200);
    });

    test('serves the canonical spelling', () async {
      expect((await client.get('/about/')).status, 200);
      expect((await client.get('/')).status, 200);
    });
  });

  test('always redirects the prefix of a prefixed site', () async {
    final client = await _start(slashModule(DocsAlwaysSite.new, []));

    final response = await client.get('/docs');

    expect(response.headers['location'], '/docs/');
  });

  test('ignore serves both spellings', () async {
    final client = await _start(slashModule(IgnoreSite.new, []));

    expect((await client.get('/about')).status, 200);
    expect((await client.get('/about/')).status, 200);
  });

  test('a hook answers before the redirect', () async {
    final client = await _start(
      CatalogPagesModule<AdminSite>(AdminSite.new, [
        markedPage('/'),
        markedPage('/about'),
      ]),
    );

    expect((await client.get('/admin/about/')).status, 401);
  });
}
