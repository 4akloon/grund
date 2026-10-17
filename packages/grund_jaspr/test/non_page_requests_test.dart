import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/page/non_page_requests.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/sites.dart';

void main() {
  final requests = NonPageRequests(const JasprConfig());

  group('isPageRequest', () {
    for (final (path, expected) in [
      ('/', true),
      ('/projects/alpha', true),
      ('/projects/a.html', true),
      ('/feed.xml', true),
      ('/page.htm', true),
      ('/projects/x.png', false),
      ('/projects/foo.md', false),
      ('/a.b/c', true),
      ('/a.b/c.png', false),
      ('/a.PNG', false),
      ('/a.HTML', true),
    ]) {
      test('$path is ${expected ? 'a page' : 'a file'} request', () {
        expect(requests.isPageRequest(Uri.parse(path)), expected);
      });
    }

    test('uses the pageSuffixes of the config', () {
      final custom = NonPageRequests(const JasprConfig(pageSuffixes: ['rss']));

      expect(custom.isPageRequest(Uri.parse('/feed.rss')), isTrue);
      expect(custom.isPageRequest(Uri.parse('/feed.xml')), isFalse);
    });
  });

  test('notFound throws a file_not_found NotFoundException', () {
    expect(
      () => requests.notFound(Uri.parse('/a.png')),
      throwsA(
        isA<NotFoundException>()
            .having((e) => e.code, 'code', 'file_not_found')
            .having((e) => e.message, 'message', 'There is no file /a.png.'),
      ),
    );
  });

  group('over HTTP', () {
    test('a file-like path never reaches the page builder', () async {
      var builds = 0;
      final client = await startPublic([
        homePage(const Component.text('Home')),
        Page(
          '/projects/:slug',
          build: (_) {
            builds++;
            return const Component.text('project');
          },
        ),
      ]);

      final png = await client.get('/projects/x.png');
      final md = await client.get('/projects/foo.md');
      final page = await client.get('/projects/alpha');
      final suffix = await client.get('/projects/a.html');

      expect(png.status, 404);
      expect(png.headers['content-type'], 'application/problem+json');
      expect(png.json, containsPair('code', 'file_not_found'));
      expect(md.json, containsPair('code', 'file_not_found'));
      expect(page.status, 200);
      expect(suffix.status, 200);
      expect(builds, 2);
    });

    test('a dotted last segment is a file request, not a page slug', () async {
      var builds = 0;
      final client = await startPublic([
        homePage(const Component.text('Home')),
        Page(
          '/projects/:slug',
          build: (_) {
            builds++;
            return const Component.text('project');
          },
        ),
      ]);

      final response = await client.get('/projects/v1.2');

      expect(response.status, 404);
      expect(response.json, containsPair('code', 'file_not_found'));
      expect(builds, 0);
    });

    test('the fallback of a site answers a file path with JSON', () async {
      final client = await PagesApp.start([
        const JasprModule(),
        const UsersPagesModule(),
      ]);

      final file = await client.get('/admin/logo.png', headers: adminHeaders);
      final page = await client.get('/admin/nope', headers: adminHeaders);

      expect(file.status, 404);
      expect(file.headers['content-type'], 'application/problem+json');
      expect(file.json, containsPair('code', 'file_not_found'));
      expect(page.status, 404);
      expect(page.text, contains('admin not found'));
    });
  });
}
