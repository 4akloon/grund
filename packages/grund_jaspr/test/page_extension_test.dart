import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/site/page_registry.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sites.dart';

/// Answers `Accept: text/markdown` in [respond] and `*.md` files in
/// [claim], and counts the calls.
final class Recording extends PageExtension {
  Recording({this.failClaim = false});

  final bool failClaim;
  var responds = 0;
  var claims = 0;

  @override
  Future<HttpResponse?> respond(HttpCtx c, PageMatch match) async {
    responds++;
    if (c.headers.stringOrNull('accept') != 'text/markdown') return null;
    return HttpResponse.text('# ${match.page.path}');
  }

  @override
  Future<HttpResponse?> claim(HttpCtx c, Uri uri) async {
    claims++;
    if (failClaim) throw StateError('claim failed');
    if (!uri.path.endsWith('.md')) return null;
    return HttpResponse.text('md ${uri.path}');
  }
}

const _markdown = {'accept': 'text/markdown'};

// Every site needs an index page; [pages] get one unless they declare it.
Future<TestApp> _publicApp(List<Page> pages) => startCatalogApp([
  CatalogPagesModule<PublicSite>(PublicSite.new, [
    if (!pages.any((page) => page.path == '/')) markedPage('/'),
    ...pages,
  ]),
]);

void main() {
  group('respond', () {
    test('answers instead of the page and skips the builder', () async {
      final extension = Recording();
      var built = 0;
      final app = await _publicApp([
        Page(
          '/projects/:slug',
          extensions: [extension],
          build: (_) {
            built++;
            return const Component.text('html');
          },
        ),
      ]);
      final response = await TestClient.of(
        app,
      ).get('/projects/alpha', headers: _markdown);
      expect(response.text, '# /projects/:slug');
      expect(built, 0);
    });

    test('lets the page render when every extension returns null', () async {
      final extension = Recording();
      final app = await _publicApp([
        markedPage('/projects/:slug', extensions: [extension]),
      ]);
      final response = await TestClient.of(app).get('/projects/alpha');
      expect(response.text, contains('id:/projects/:slug'));
      expect(extension.responds, 1);
    });

    test('is not called for the extensions of another page', () async {
      final other = Recording();
      final app = await _publicApp([
        markedPage('/a'),
        markedPage('/b', extensions: [other]),
      ]);
      await TestClient.of(app).get('/a', headers: _markdown);
      expect(other.responds, 0);
    });

    test('never runs for a guest on a guarded site', () async {
      final extension = Recording();
      final app = await startCatalogApp([
        CatalogPagesModule<AdminSite>(AdminSite.new, [
          markedPage('/'),
          markedPage('/guarded', extensions: [extension]),
        ]),
      ]);
      final client = TestClient.of(app);
      final guest = await client.get('/admin/guarded', headers: _markdown);
      expect(guest.status, 401);
      expect(extension.responds, 0);
      final admin = await client.get(
        '/admin/guarded',
        headers: {..._markdown, ...adminHeaders},
      );
      expect(admin.text, '# /admin/guarded');
    });
  });

  group('claim', () {
    test('serves a file variant under a page route', () async {
      final extension = Recording();
      final app = await _publicApp([
        markedPage('/projects/:slug', extensions: [extension]),
      ]);
      final response = await TestClient.of(app).get('/projects/foo.md');
      expect(response.status, 200);
      expect(response.text, 'md /projects/foo.md');
    });

    test('serves a file variant on the site fallback', () async {
      final app = await _publicApp([
        markedPage('/', extensions: [Recording()]),
      ]);
      final response = await TestClient.of(app).get('/x.md');
      expect(response.text, 'md /x.md');
    });

    test('answers 404 file_not_found when nobody claims', () async {
      final app = await _publicApp([
        markedPage('/projects/:slug', extensions: [Recording()]),
      ]);
      final response = await TestClient.of(app).get('/projects/foo.txt');
      expect(response.status, 404);
      expect((response.json! as Map)['code'], 'file_not_found');
    });

    test('answers 404 when no page has an extension', () async {
      final app = await _publicApp([markedPage('/projects/:slug')]);
      final response = await TestClient.of(app).get('/projects/foo.md');
      expect(response.status, 404);
    });

    test('is not called for a page request', () async {
      final extension = Recording();
      final app = await _publicApp([
        markedPage('/projects/:slug', extensions: [extension]),
      ]);
      await TestClient.of(app).get('/projects/alpha');
      await TestClient.of(app).get('/missing');
      expect(extension.claims, 0);
    });

    test('is called once for an extension shared by two pages', () async {
      final shared = Recording();
      final app = await _publicApp([
        markedPage('/a', extensions: [shared]),
        markedPage('/b', extensions: [shared]),
      ]);
      await TestClient.of(app).get('/a/f.txt');
      expect(shared.claims, 1);
    });

    test('does not reach the sites of other types', () async {
      final adminExtension = Recording();
      final app = await startCatalogApp([
        CatalogPagesModule<PublicSite>(PublicSite.new, [markedPage('/')]),
        CatalogPagesModule<AdminSite>(AdminSite.new, [
          markedPage('/', extensions: [adminExtension]),
        ]),
      ]);
      final response = await TestClient.of(app).get('/x.md');
      expect(response.status, 404);
      expect(adminExtension.claims, 0);
    });

    test('a failing claim is a 500', () async {
      final app = await _publicApp([
        markedPage('/', extensions: [Recording(failClaim: true)]),
      ]);
      final response = await TestClient.of(app).get('/x.md');
      expect(response.status, 500);
    });

    test('reads the extensions from the current snapshot', () async {
      final old = Recording();
      final fresh = Recording();
      final first = await _publicApp([
        markedPage('/', extensions: [old]),
      ]);
      final second = await _publicApp([
        markedPage('/', extensions: [fresh]),
      ]);
      first.injector<PageRegistry>().replace(
        second.injector<PageRegistry>().current!,
      );
      final response = await TestClient.of(first).get('/x.md');
      expect(response.status, 200);
      expect(old.claims, 0);
      expect(fresh.claims, 1);
    });
  });
}
