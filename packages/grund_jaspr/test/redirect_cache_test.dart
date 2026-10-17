import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/file_sites.dart';
import 'helpers/sites.dart';

final class _GuardedSite extends AdminSite {
  _GuardedSite(super.injector);

  @override
  List<SiteFile> get files => [textFile('/robots.txt')];
}

final class _OpenSite extends PageSite {
  _OpenSite(super.injector);

  @override
  List<SiteFile> get files => [textFile('/robots.txt')];
}

Page _about({PageHooks hooks = const PageHooks()}) => Page(
  '/about',
  hooks: hooks,
  alternates: [PageAlternate.markdown((c, m) => '# about')],
  build: markedPage('/about').build,
);

Future<TestClient> _start<S extends PageSite>(
  S Function(Injector) create,
  Page page,
) async => TestClient.of(
  await startCatalogApp([
    CatalogPagesModule<S>(create, [markedPage('/'), page]),
  ]),
);

void main() {
  const shared = 'max-age=3600';
  const private = 'private, max-age=3600';

  group('a site without hooks', () {
    late TestClient client;
    setUp(() async => client = await _start(_OpenSite.new, _about()));

    for (final path in ['/about/', '/about.md/', '/robots.txt/']) {
      test('$path is a shared-cacheable redirect', () async {
        final response = await client.get(path);
        expect(response.status, 308);
        expect(response.headers['cache-control'], shared);
      });
    }
  });

  group('a site with hooks', () {
    late TestClient client;
    setUp(() async => client = await _start(_GuardedSite.new, _about()));

    for (final path in [
      '/admin/about/',
      '/admin/about.md/',
      '/admin/robots.txt/',
    ]) {
      test('$path is a private redirect', () async {
        final response = await client.get(path, headers: adminHeaders);
        expect(response.status, 308);
        expect(response.headers['cache-control'], private);
      });
    }
  });

  group('a page with hooks on a site without', () {
    late TestClient client;
    setUp(() async {
      client = await _start(
        _OpenSite.new,
        _about(hooks: const PageHooks(use: [HookRef<CurrentUserHook>.type()])),
      );
    });

    for (final path in ['/about/', '/about.md/']) {
      test('$path is a private redirect', () async {
        final response = await client.get(path);
        expect(response.status, 308);
        expect(response.headers['cache-control'], private);
      });
    }
  });
}
