import 'package:grund/grund.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/catalog_app.dart';
import 'helpers/sites.dart';

List<Module> _modules() => [
  CatalogPagesModule<PublicSite>(PublicSite.new, [
    markedPage('/'),
    markedPage('/about'),
    markedPage('/projects/new'),
    markedPage('/projects/:slug'),
    markedPage('/docs/new/edit'),
    markedPage('/docs/:slug/view'),
    markedPage('/:section/x'),
    markedPage('/:a'),
  ]),
  CatalogPagesModule<AdminSite>(AdminSite.new, [
    markedPage('/'),
    markedPage('/users'),
    markedPage('/users/:id'),
  ]),
];

const _paths = [
  '/',
  '//',
  '/about',
  '/about/',
  // TestClient parses a leading "//" as an authority; the matcher test
  // covers "//about", here the empty segments are inside the path.
  '/projects//alpha',
  '/admin//users',
  '/ABOUT',
  '/%61bout',
  '/about%2Fx',
  '/%61dmin',
  '/admin',
  '/admin/',
  '/admin/users',
  '/admin/users/7',
  '/admin/users/a%2Fb',
  '/%61dmin/users/7',
  '/admin/x',
  '/admin/nothing',
  '/projects/new',
  '/projects/alpha',
  '/projects/a%2Fb',
  '/projects',
  '/docs/new/view',
  '/docs/new/edit',
  '/other/x',
  '/nothing/here',
  '/about.png',
  '/projects/foo.md',
  '/about.html',
  '/static/app.css',
  '/static',
  '/static/',
  '/robots.txt',
  '/robots.txt/',
  '/LICENSE',
  '/LICENSE/',
  '/%zz',
];

final _marker = RegExp(r'<h1>id:([^<]*)</h1>');

void main() {
  test('catalog.match agrees with the pages the server serves', () async {
    final app = await startCatalogApp(
      _modules(),
      config: const JasprConfig(rootFiles: ['robots.txt', 'LICENSE']),
    );
    final client = TestClient.of(app);
    final catalog = app.injector<PageCatalog>();
    final disagreements = <String>[];

    for (final path in _paths) {
      final response = await client.get(path, headers: adminHeaders);
      final served = _servedBy(response.text);
      final match = catalog.match(Uri.parse('http://localhost$path'));
      final matched = match == null ? null : _label(match.page);
      if (served != matched) {
        disagreements.add('$path: served $served, matched $matched');
      }
    }

    expect(disagreements, isEmpty);
  });
}

String _label(SitePage page) =>
    '${page.site is AdminSite ? 'admin' : 'public'} ${page.page.path}';

// The page a response shows, named like [_label], or null for a not found.
String? _servedBy(String body) {
  final id = _marker.firstMatch(body)?.group(1);
  if (id == null) return null;
  return '${body.contains('class="admin"') ? 'admin' : 'public'} $id';
}
