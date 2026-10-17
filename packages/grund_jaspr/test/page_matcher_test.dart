import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/page/page_matcher.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/no_injector.dart';
import 'helpers/sites.dart';

// The sites only need an injector to be constructed; the matcher reads
// paths.
SitePage _page(String fullPath, {PageSite? site}) => SitePage(
  site: site ?? _site,
  page: Page(fullPath, build: (_) => const Component.text('')),
  path: fullPath,
);

final PageSite _site = PublicSite(const NoInjector());

PageMatcher _matcher(List<String> paths, {List<String> sites = const []}) =>
    PageMatcher([for (final path in paths) _page(path)], sitePaths: sites);

String? _match(PageMatcher matcher, String url) =>
    matcher.match(Uri.parse('http://x$url').pathSegments)?.page.path;

void main() {
  final matcher = _matcher([
    '/',
    '/about',
    '/projects/:slug',
    '/projects/new',
    '/admin',
    '/admin/users/:id',
  ]);

  group('PageMatcher', () {
    test('binds a parameter', () {
      final match = matcher.match(Uri.parse('/projects/alpha').pathSegments);

      expect(match!.page.path, '/projects/:slug');
      expect(match.params, {'slug': 'alpha'});
    });

    test('a literal beats a parameter', () {
      expect(_match(matcher, '/projects/new'), '/projects/new');
    });

    test('/ matches the index', () {
      expect(_match(matcher, '/'), '/');
    });

    test('matches the page of another site by full path', () {
      final match = matcher.match(Uri.parse('/admin/users/7').pathSegments);

      expect(match!.page.path, '/admin/users/:id');
      expect(match.params, {'id': '7'});
      expect(_match(matcher, '/about'), '/about');
    });

    test('drops empty segments', () {
      expect(_match(matcher, '//about'), '/about');
      expect(_match(matcher, '/about/'), '/about');
    });

    test('the case matters', () {
      expect(_match(matcher, '/ABOUT'), isNull);
    });

    test('decodes a percent-encoded segment', () {
      expect(_match(matcher, '/%61bout'), '/about');
    });

    test('an encoded slash stays inside one segment', () {
      final match = matcher.match(Uri.parse('/projects/a%2Fb').pathSegments);

      expect(match!.params, {'slug': 'a/b'});
      expect(_match(matcher, '/about%2Fx'), isNull);
    });

    test('backtracks from a literal branch that fails', () {
      final backtracking = _matcher(['/docs/new/edit', '/docs/:slug/view']);

      expect(_match(backtracking, '/docs/new/view'), '/docs/:slug/view');
      expect(_match(backtracking, '/docs/new/edit'), '/docs/new/edit');
    });

    test('a path that is a prefix of a page matches nothing', () {
      expect(_match(matcher, '/projects'), isNull);
      expect(_match(matcher, '/admin/users'), isNull);
    });

    test('a site path claims what lies below it before a parameter does', () {
      final claimed = _matcher(['/:a/x', '/admin'], sites: ['/admin', '']);

      expect(_match(claimed, '/admin/x'), isNull);
      expect(_match(claimed, '/other/x'), '/:a/x');
    });
  });
}
