import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/site/page_registry.dart';
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/sites.dart';
import 'helpers/validation_sites.dart';

Matcher _throwsError<T extends Object>([String? text]) => throwsA(
  isA<T>().having(
    (e) => e is GrundError ? e.message : '$e',
    'message',
    text == null ? anything : contains(text),
  ),
);

void main() {
  group('global site rules', () {
    test('two modules declaring the same site type are rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
          const _SecondAdminModule(),
        ]),
        _throwsError<DuplicateSiteError>(),
      );
    });

    test('two sites on the same path are rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
          const SiteWithPagesModule<OtherAdminSite>(OtherAdminSite.new),
        ]),
        _throwsError<DuplicateSitePathError>('/admin'),
      );
    });

    test('two root sites are rejected as a duplicate path', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          publicSite(),
          const SiteWithPagesModule<SecondRootSite>(SecondRootSite.new),
        ]),
        _throwsError<DuplicateSitePathError>(),
      );
    });

    test('a site nested in another site is rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
          const SiteWithPagesModule<ReportsSite>(ReportsSite.new),
        ]),
        _throwsError<NestedSitePathError>('/admin/reports'),
      );
    });

    test('the root site is no outer site of another', () async {
      final app = await StartedPagesApp.start([
        const JasprModule(),
        publicSite(),
        const SiteWithPagesModule<AdminSite>(AdminSite.new),
      ]);
      expect(app<PageRegistry>().current!.sites, hasLength(2));
    });

    test('a site without the "/" page is rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          publicSite(withIndex: false, extra: ['/about']),
        ]),
        _throwsError<MissingSiteIndexError>(),
      );
    });

    test('a page that lies under another site is rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          publicSite(extra: ['/admin/help']),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
        ]),
        _throwsError<MisplacedPagePathError>('/admin/help'),
      );
    });

    test('a page equal to another site path is rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          publicSite(extra: ['/admin']),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
        ]),
        _throwsError<MisplacedPagePathError>(),
      );
    });

    test('a site factory returning another type is rejected', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          const SiteWithPagesModule<AdminSite>(_superAdmin),
        ]),
        _throwsError<MismatchedSiteTypeError>('SuperAdminSite'),
      );
    });

    test('a subclass site is a separate site from its base', () async {
      final app = await StartedPagesApp.start([
        const JasprModule(),
        const SiteWithPagesModule<AdminSite>(AdminSite.new),
        const SiteWithPagesModule<SuperAdminSite>(SuperAdminSite.new),
      ]);
      expect(app<PageRegistry>().current!.pages, hasLength(2));
    });

    test('the index of the base site does not serve its subclass', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          const SiteWithPagesModule<AdminSite>(AdminSite.new),
          const SiteWithPagesModule<SuperAdminSite>(
            SuperAdminSite.new,
            withIndex: false,
            extra: ['/more'],
          ),
        ]),
        _throwsError<MissingSiteIndexError>('SuperAdminSite'),
      );
    });

    test('an application without sites starts', () async {
      final app = await StartedPagesApp.start([const JasprModule()]);
      expect(app<PageRegistry>().current!.sites, isEmpty);
    });
  });
}

AdminSite _superAdmin(Injector i) => SuperAdminSite(i);

/// Declares [AdminSite] a second time in another module.
final class _SecondAdminModule extends Module {
  const _SecondAdminModule();

  @override
  List<Binding<Object>> get bindings => Pages.site<AdminSite>(AdminSite.new);
}
