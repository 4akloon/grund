import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/sites.dart';

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
  test('an API route with a :param segment beats the site fallback', () async {
    final client = await startPublic(
      [homePage(const UrlPage())],
      modules: const [ItemsModule()],
    );

    final api = await client.get('/items/7');
    final fallback = await client.get('/items/7/more');

    expect(api.json, {'item': '7'});
    expect(fallback.status, 404);
    expect(fallback.text, contains('public not found'));
  });

  test('HEAD of an API GET route is answered by the API, not a page', () async {
    final client = await startPublic(
      [homePage(const UrlPage())],
      modules: const [ItemsModule()],
    );

    final response = await client.request('HEAD', '/items/7');

    expect(response.status, 200);
    expect(response.headers['content-type'], contains('application/json'));
  });

  test('an API GET / next to the pages is a DuplicateRouteError', () async {
    final started = startPublic(
      [homePage(const UrlPage())],
      modules: const [RootModule()],
    );

    await expectLater(started, throwsA(isA<DuplicateRouteError>()));
  });
}
