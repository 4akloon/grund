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
  Recording({this.failClaim = false, this.answers = true});

  final bool failClaim;
  // Whether a `.md` file is answered; otherwise claim only counts.
  final bool answers;
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
    if (!answers || !uri.path.endsWith('.md')) return null;
    return HttpResponse.text('md ${uri.path}');
  }
}

/// Throws [error] from `respond` and `claim`.
final class Throwing extends PageExtension {
  Throwing(this.error);

  final Object error;

  @override
  Future<HttpResponse?> respond(HttpCtx c, PageMatch match) async =>
      throw error;

  @override
  Future<HttpResponse?> claim(HttpCtx c, Uri uri) async => throw error;
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

    test('a throwing respond is a 500', () async {
      final app = await _publicApp([
        markedPage('/', extensions: [Throwing(StateError('boom'))]),
      ]);
      final response = await TestClient.of(app).get('/', headers: _markdown);
      expect(response.status, 500);
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

    test(
      'runs after the site hooks: a guest gets 401, nothing claimed',
      () async {
        final extension = Recording();
        final app = await startCatalogApp([
          CatalogPagesModule<AdminSite>(AdminSite.new, [
            markedPage('/', extensions: [extension]),
          ]),
        ]);
        final client = TestClient.of(app);
        final guest = await client.get('/admin/x.md');
        expect(guest.status, 401);
        expect(extension.claims, 0);
        final admin = await client.get('/admin/x.md', headers: adminHeaders);
        expect(admin.text, 'md /admin/x.md');
      },
    );

    test('is not asked for a page with its own hooks.use', () async {
      final guarded = Recording();
      final open = Recording(answers: false);
      final app = await _publicApp([
        markedPage(
          '/billing',
          hooks: const PageHooks(use: [HookRef<AdminGuard>.type()]),
          extensions: [guarded],
        ),
        markedPage('/docs', extensions: [open]),
      ]);
      final client = TestClient.of(app);
      final response = await client.get('/billing.md');
      expect(response.status, 404);
      expect((response.json! as Map)['code'], 'file_not_found');
      expect(guarded.claims, 0);
      await client.get('/billing.md');
      expect(open.claims, 2);
    });

    test('a page with only skip stays in the claim set', () async {
      final extension = Recording();
      final app = await startCatalogApp([
        CatalogPagesModule<_SkipSite>(_SkipSite.new, [
          markedPage('/', extensions: [extension]),
          markedPage('/a', hooks: const PageHooks(skip: [AdminGuard])),
        ]),
      ]);
      final response = await TestClient.of(
        app,
      ).get('/admin/x.md', headers: adminHeaders);
      expect(response.status, 200);
      expect(extension.claims, 1);
    });

    test('works for HEAD', () async {
      final app = await _publicApp([
        markedPage('/', extensions: [Recording()]),
      ]);
      final response = await TestClient.of(app).request('HEAD', '/x.md');
      expect(response.status, 200);
    });

    test('a NotFoundException of an extension is the JSON 404', () async {
      final app = await _publicApp([
        markedPage('/', extensions: [Throwing(const NotFoundException())]),
      ]);
      final response = await TestClient.of(app).get('/x.md');
      expect(response.status, 404);
      expect(response.json, isA<Map<String, Object?>>());
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

final class _SkipSite extends AdminSite {
  _SkipSite(super.injector);

  @override
  List<Type> get skippableHooks => const [AdminGuard];
}
