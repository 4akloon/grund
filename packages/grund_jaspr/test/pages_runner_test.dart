import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/site/page_registry.dart';
import 'package:grund_jaspr/src/site/pages_runner.dart';
import 'package:grund_jaspr/src/site/site_validator.dart';
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/sites.dart';
import 'helpers/validation_sites.dart';

Set<String> _pagePaths(PageRegistry registry) => {
  for (final api in registry.current!.pages)
    for (final page in api.pages) '${api.site.path}${page.path}',
};

void main() {
  group('PagesRunner', () {
    late PageRegistry registry;
    late PagesRunner runner;

    setUp(() {
      registry = PageRegistry();
      runner = PagesRunner(registry, const SiteValidator());
    });

    test('is named pages and the registry is empty before prepare', () {
      expect(runner.name, 'pages');
      expect(registry.current, isNull);
    });

    test('is part of the started application', () async {
      final app = await StartedPagesApp.start([
        const JasprModule(),
        publicSite(),
      ]);
      expect(app.injector.all<Runner>().map((r) => r.name), contains('pages'));
    });

    test('prepare on an empty graph passes', () async {
      final app = await StartedPagesApp.start([const JasprModule()]);
      await runner.prepare(app.injector);
      expect(registry.current!.sites, isEmpty);
    });

    test('prepare stores the snapshot of the injector', () async {
      final a = await StartedPagesApp.start([
        const JasprModule(),
        publicSite(extra: ['/x']),
      ]);
      await runner.prepare(a.injector);
      expect(_pagePaths(registry), {'/', '/x'});
    });

    test('reassemble replaces the snapshot and reports no change', () async {
      final a = await StartedPagesApp.start([
        const JasprModule(),
        publicSite(extra: ['/x']),
      ]);
      final b = await StartedPagesApp.start([
        const JasprModule(),
        publicSite(extra: ['/x', '/y']),
        const SiteWithPagesModule<BlogSite>(BlogSite.new),
      ]);
      await runner.prepare(a.injector);
      final report = await runner.reassemble(b.injector);
      expect(_pagePaths(registry), containsAll(['/x', '/y', '/blog/']));
      expect(registry.current!.sites, hasLength(2));
      expect(report, same(ReassembleReport.none));
    });

    test('a failing reassemble keeps the previous snapshot', () async {
      final a = await StartedPagesApp.start([
        const JasprModule(),
        publicSite(extra: ['/x']),
      ]);
      final invalid = await StartedPagesApp.startUnchecked([
        const JasprModule(),
        const SiteWithPagesModule<AdminSite>(AdminSite.new),
        const SiteWithPagesModule<ReportsSite>(ReportsSite.new),
      ]);
      await runner.prepare(a.injector);
      final before = registry.current;
      await expectLater(
        runner.reassemble(invalid.injector),
        throwsA(isA<NestedSitePathError>()),
      );
      expect(registry.current, same(before));
    });

    test('a failing prepare leaves the registry empty', () async {
      final invalid = await StartedPagesApp.startUnchecked([
        const JasprModule(),
        publicSite(withIndex: false, extra: ['/about']),
      ]);
      await expectLater(
        runner.prepare(invalid.injector),
        throwsA(isA<MissingSiteIndexError>()),
      );
      expect(registry.current, isNull);
    });
  });
}
