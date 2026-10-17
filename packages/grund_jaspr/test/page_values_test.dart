import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

final class _Site extends PageSite {
  _Site(super.injector);
}

void main() {
  test('Page defaults', () {
    const page = Page('/', build: _build);
    expect(page.meta.title, '');
    expect(page.meta.sitemap.included, isNull);
    expect(page.meta.nav, isNull);
    expect(page.hooks.skip, isEmpty);
    expect(page.hooks.use, isEmpty);
    expect(page.extensions, isEmpty);
  });

  test('PageSitemap can include a page explicitly', () {
    expect(const PageSitemap(included: true).included, isTrue);
    expect(const PageSitemap(included: false).included, isFalse);
  });

  test('PageNav defaults', () {
    const nav = PageNav();
    expect(nav.group, 'main');
    expect(nav.order, 0);
    expect(nav.label, isNull);
  });

  group('PageSite defaults', () {
    late _Site site;
    setUp(() => site = _Site(_NoInjector()));

    test('has no prefix, hooks or base URL', () {
      expect(site.path, '');
      expect(site.use, isEmpty);
      expect(site.skippableHooks, isEmpty);
      expect(site.sitemapBaseUrl, isNull);
    });

    test('shell returns the same content', () {
      const content = Component.text('x');
      expect(identical(site.shell(content), content), isTrue);
    });

    test('notFound is a text component', () {
      expect(site.notFound(), isA<Component>());
    });
  });

  test('PageMatch has no params by default', () {
    final site = _Site(_NoInjector());
    final match = PageMatch(
      page: SitePage(
        site: site,
        page: const Page('/', build: _build),
        path: '/',
      ),
    );
    expect(match.params, isEmpty);
  });

  test('InvalidSitePathError names the path and the reason', () {
    const error = InvalidSitePathError(path: '/a/', reason: 'bad end');
    expect(error.message, allOf(contains('/a/'), contains('bad end')));
  });
}

Component _build(Object c) => const Component.text('x');

final class _NoInjector implements Injector {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
