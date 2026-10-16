import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';
import 'helpers/temp_dir.dart';

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

void main() {
  test('GET / renders the page as UTF-8 HTML that is not cached', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
    expect(response.headers['cache-control'], 'private, no-cache');
    expect(response.text, contains('<html'));
    expect(response.text, contains('url /'));
  });

  test('a deep path and its query reach the page', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/a/b?x=1&y=%20z');

    expect(response.text, contains('url /a/b?x=1&amp;y=%20z'));
  });

  test('cookies and headers a page sets reach the client', () async {
    final client = await PagesApp.start([
      const JasprModule(app: CookiePage.new),
    ]);

    final response = await client.get('/');

    expect(response.headers.all('set-cookie'), hasLength(2));
    expect(response.headers['x-page'], 'yes');
  });

  test(
    'a content type, status and cache header of the page are kept',
    () async {
      final client = await PagesApp.start([
        const JasprModule(app: FeedPage.new),
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
      final client = await PagesApp.start([
        const JasprModule(app: BrokenPage.new),
      ]);
      return client.get('/');
    }, stderr: () => _CapturedStderr(stderrText));

    expect(response.status, 500);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.text, isNot(contains('secret detail')));
    expect(stderrText.toString(), contains('secret detail'));
  });

  test('the application component is built again for every request', () async {
    var built = 0;
    final client = await PagesApp.start([
      JasprModule(
        app: () {
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
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.request('HEAD', '/');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
  });

  test('POST to a page is a 405', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.post('/');

    expect(response.status, 405);
  });

  test('a page reads DI and a value a global hook set', () async {
    final client = await PagesApp.start(
      [
        const JasprModule(app: ServicePage.new, imports: [GreeterModule()]),
      ],
      use: [HookRef.instance(const VisitorHook())],
    );

    final response = await client.get('/', headers: {'x-visitor': 'ann'});

    expect(response.text, contains('hello from DI, ann'));
  });

  test('an API route wins over the page catch-all', () async {
    final client = await PagesApp.start([
      const JasprModule(app: UrlPage.new),
      const ApiModule(),
    ]);

    final response = await client.get('/api/hello');

    expect(response.json, {'hello': 'api'});
  });

  test('a file of the static directory is served with its type', () async {
    final dir = TempDir.create();
    File('${dir.path}/app.css').writeAsStringSync('body{}');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(staticDirectory: dir.path),
      ),
    ]);

    final response = await client.get('/app.css');

    expect(response.headers['content-type'], 'text/css; charset=utf-8');
    expect(response.text, 'body{}');
  });

  test('a missing non-page file is a 404, not a page', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/missing.png');

    expect(response.status, 404);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.json, containsPair('code', 'file_not_found'));
  });

  test('a path with a page suffix of the config is a page', () async {
    final client = await PagesApp.start([
      const JasprModule(
        app: UrlPage.new,
        config: JasprConfig(pageSuffixes: ['rss']),
      ),
    ]);

    final rss = await client.get('/feed.rss');
    final xml = await client.get('/feed.xml');

    expect(rss.status, 200);
    expect(rss.text, contains('url /feed.rss'));
    expect(xml.status, 404);
  });

  test('a malformed Cookie header does not break a page', () async {
    final client = await PagesApp.start([
      const JasprModule(app: FlashPage.new),
    ]);

    final response = await client.get(
      '/',
      headers: {'cookie': 'flash=yes; =; broken; a="b'},
    );

    expect(response.status, 200);
    expect(response.text, contains('flash yes'));
  });

  for (final target in [
    '/../pubspec.yaml',
    '/%2e%2e/pubspec.yaml',
    '/a/%2F..%2F..%2Fpubspec.yaml',
    '/.hidden',
    '/a%5C..%5Cx.css',
  ]) {
    test('$target never leaves the static directory', () async {
      final dir = TempDir.create();
      Directory('${dir.path}/web').createSync();
      File('${dir.path}/pubspec.yaml').writeAsStringSync('secret');
      File('${dir.path}/web/.hidden').writeAsStringSync('secret');
      final client = await PagesApp.start([
        JasprModule(
          app: UrlPage.new,
          config: JasprConfig(staticDirectory: '${dir.path}/web'),
        ),
      ]);

      final response = await client.get(target);

      expect(response.text, isNot(contains('secret')));
    });
  }

  test('a symlink out of the static directory is not served', () async {
    final dir = TempDir.create();
    Directory('${dir.path}/web').createSync();
    File('${dir.path}/secret.txt').writeAsStringSync('secret');
    Link('${dir.path}/web/link.txt').createSync('${dir.path}/secret.txt');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(staticDirectory: '${dir.path}/web'),
      ),
    ]);

    final response = await client.get('/link.txt');

    expect(response.status, 404);
  });
}

/// Collects what Jaspr writes to stderr, where it prints a failed build.
final class _CapturedStderr implements Stdout {
  _CapturedStderr(this._text);

  final StringBuffer _text;

  @override
  void write(Object? object) => _text.write(object);

  @override
  void writeln([Object? object = '']) => _text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
