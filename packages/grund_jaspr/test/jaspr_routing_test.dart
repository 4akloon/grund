import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';
import 'helpers/temp_dir.dart';

final class ItemsApi extends HttpApi {
  ItemsApi(super.injector);

  @override
  String get path => '/items';

  @override
  List<Route> get routes => [
    Route.get('/:id', (c) => {'item': c.path.string('id')}),
  ];
}

final class RootApi extends HttpApi {
  RootApi(super.injector);

  @override
  String get path => '/';

  @override
  List<Route> get routes => [
    Route.get('/', (_) => {'root': 'api'}),
  ];
}

final class ItemsModule extends Module {
  const ItemsModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ItemsApi>(ItemsApi.new, dependsOn: const []),
  ];
}

final class RootModule extends Module {
  const RootModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<RootApi>(RootApi.new, dependsOn: const []),
  ];
}

void main() {
  test('an API route with a :param segment beats the page catch-all', () async {
    final client = await PagesApp.start([
      const JasprModule(app: UrlPage.new),
      const ItemsModule(),
    ]);

    final api = await client.get('/items/7');
    final page = await client.get('/items/7/more');

    expect(api.json, {'item': '7'});
    expect(page.text, contains('url /items/7/more'));
  });

  test('HEAD of an API GET route is answered by the API, not a page', () async {
    final client = await PagesApp.start([
      const JasprModule(app: UrlPage.new),
      const ItemsModule(),
    ]);

    final response = await client.request('HEAD', '/items/7');

    expect(response.status, 200);
    expect(response.headers['content-type'], contains('application/json'));
  });

  test('an extensionless static file wins over a page', () async {
    final dir = TempDir.create();
    File('${dir.path}/LICENSE').writeAsStringSync('the license');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(staticDirectory: dir.path),
      ),
    ]);

    final response = await client.get('/LICENSE');

    expect(response.text, 'the license');
  });

  test('a static file with a page suffix wins over the page', () async {
    final dir = TempDir.create();
    File('${dir.path}/feed.rss').writeAsStringSync('<rss/>');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(
          staticDirectory: dir.path,
          pageSuffixes: const ['rss'],
        ),
      ),
    ]);

    final response = await client.get('/feed.rss');

    expect(response.text, '<rss/>');
  });

  test('an API GET / next to the pages is a DuplicateRouteError', () async {
    final started = PagesApp.start([
      const JasprModule(app: UrlPage.new),
      const RootModule(),
    ]);

    await expectLater(started, throwsA(isA<DuplicateRouteError>()));
  });
}
