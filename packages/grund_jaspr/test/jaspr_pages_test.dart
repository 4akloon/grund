import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/sites.dart';

final class HelloApi extends HttpApi {
  HelloApi(super.injector);

  @override
  String get path => '/api';

  @override
  List<Route> get routes => [
    Route.get('/hello', (_) => {'hello': 'api'}),
  ];
}

final class ApiModule extends Module {
  const ApiModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HelloApi>(HelloApi.new, dependsOn: const []),
  ];
}

Page pageAt(String path, Component Function() component) =>
    Page(path, build: (_) => component());

void main() {
  test('GET / renders the page as UTF-8 HTML that is not cached', () async {
    final client = await startPublic([homePage(const UrlPage())]);

    final response = await client.get('/');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
    expect(response.headers['cache-control'], 'private, no-cache');
    expect(response.text, contains('<html'));
    expect(response.text, contains('url /'));
  });

  test('a deep path and its query reach the page', () async {
    final client = await startPublic([
      homePage(const UrlPage()),
      pageAt('/a/b', UrlPage.new),
    ]);

    final response = await client.get('/a/b?x=1&y=%20z');

    expect(response.text, contains('url /a/b?x=1&amp;y=%20z'));
  });

  test('cookies and headers a page sets reach the client', () async {
    final client = await startPublic([homePage(const CookiePage())]);

    final response = await client.get('/');

    final cookies = response.headers.all('set-cookie');
    expect(cookies, hasLength(2));
    expect(cookies[0], startsWith('a=1'));
    expect(cookies[1], startsWith('b=2'));
    expect(response.headers['x-page'], 'yes');
  });

  test(
    'a content type, status and cache header of the page are kept',
    () async {
      final client = await startPublic([
        homePage(const UrlPage()),
        pageAt('/feed.xml', FeedPage.new),
      ]);

      final response = await client.get('/feed.xml');

      expect(response.status, 203);
      expect(response.headers['content-type'], 'application/xml');
      expect(response.headers['cache-control'], 'max-age=60');
    },
  );

  test('a page that throws answers a 500 problem without the detail', () async {
    final stderrText = StringBuffer();
    final response = await IOOverrides.runZoned(() async {
      final client = await startPublic([homePage(const BrokenPage())]);
      return client.get('/');
    }, stderr: () => CapturedStderr(stderrText));

    expect(response.status, 500);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.text, isNot(contains('secret detail')));
    expect(stderrText.toString(), contains('secret detail'));
  });

  test('the page builder is called again for every request', () async {
    var built = 0;
    final client = await startPublic([
      Page(
        '/',
        build: (_) {
          built++;
          return const UrlPage();
        },
      ),
    ]);

    await client.get('/');
    await client.get('/');

    expect(built, 2);
  });

  test('HEAD answers with the headers of GET', () async {
    final client = await startPublic([homePage(const UrlPage())]);

    final response = await client.request('HEAD', '/');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
  });

  test('POST to a page is a 405', () async {
    final client = await startPublic([homePage(const UrlPage())]);

    final response = await client.post('/');

    expect(response.status, 405);
  });

  test('a page reads DI and a value a global hook set', () async {
    final client = await startPublic(
      [homePage(const ServicePage())],
      extraImports: const [GreeterModule()],
      use: [HookRef.instance(const VisitorHook())],
    );

    final response = await client.get('/', headers: {'x-visitor': 'ann'});

    expect(response.text, contains('hello from DI, ann'));
  });

  test('an API route wins over the site fallback', () async {
    final client = await startPublic(
      [homePage(const UrlPage())],
      modules: const [ApiModule()],
    );

    final response = await client.get('/api/hello');

    expect(response.json, {'hello': 'api'});
  });

  test('a malformed Cookie header does not break a page', () async {
    final client = await startPublic([homePage(const FlashPage())]);

    final response = await client.get(
      '/',
      headers: {'cookie': 'flash=yes; =; broken; a="b'},
    );

    expect(response.status, 200);
    expect(response.text, contains('flash yes'));
  });
}
