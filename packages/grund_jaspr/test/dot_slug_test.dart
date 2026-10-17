import 'package:grund/grund.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/alternate_sites.dart';
import 'helpers/catalog_app.dart';

const _dotSlugs = ['%2E', '%2E%2E', '.', '..'];

Future<TestClient> _start<S extends PageSite>(
  S Function(Injector) create,
  List<String> builds,
) async => TestClient.of(
  await startCatalogApp([
    CatalogPagesModule<S>(create, [
      Page('/', build: (_) => const Component.text('root')),
      Page(
        '/projects/:slug',
        meta: const PageMeta(sitemap: PageSitemap(included: false)),
        alternates: [
          PageAlternate.markdown((c, m) {
            builds.add('md');
            return '# x';
          }),
        ],
        build: (c) {
          builds.add('html');
          return const Component.text('x');
        },
      ),
    ]),
  ]),
);

void main() {
  for (final withBase in [false, true]) {
    group('a dot slug ${withBase ? 'with' : 'without'} baseUrl', () {
      late TestClient client;
      final builds = <String>[];
      setUp(() async {
        builds.clear();
        client = withBase
            ? await _start(BaseAltSite.new, builds)
            : await _start(PlainAltSite.new, builds);
      });

      for (final slug in _dotSlugs) {
        test('$slug on the alternate is a 404 before the builder', () async {
          final response = await client.get('/projects/$slug.md');
          expect(response.status, 404);
          expect(builds, isEmpty);
        });
      }

      // URI normalization removes the dot segment before routing, so the
      // builder never sees a dot slug on a page URL.
      for (final path in ['/projects/%2E', '/projects/%2E/']) {
        test('$path on the page is a 404 before the builder', () async {
          expect((await client.get(path)).status, 404);
          expect(builds, isEmpty);
        });
      }

      for (final path in ['/projects/%2E%2E', '/projects/%2E%2E/']) {
        test('$path on the page resolves to the parent', () async {
          expect((await client.get(path)).status, 200);
          expect(builds, isEmpty);
        });
      }
    });
  }
}
