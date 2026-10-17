import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;

import 'sites.dart';

/// A second site that claims the path of [AdminSite].
final class OtherAdminSite extends PageSite {
  /// Creates the site.
  OtherAdminSite(super.injector);

  @override
  String get path => '/admin';
}

/// A site nested in [AdminSite].
final class ReportsSite extends PageSite {
  /// Creates the site.
  ReportsSite(super.injector);

  @override
  String get path => '/admin/reports';
}

/// A site that extends [AdminSite]; it is a different site type.
base class SuperAdminSite extends AdminSite {
  /// Creates the site.
  SuperAdminSite(super.injector);

  @override
  String get path => '/super';
}

/// A blog site at `/blog`.
final class BlogSite extends PageSite {
  /// Creates the site.
  BlogSite(super.injector);

  @override
  String get path => '/blog';
}

/// A second site on the root path.
final class SecondRootSite extends PageSite {
  /// Creates the site.
  SecondRootSite(super.injector);
}

/// Declares the site [S] and a `/` page plus [extra] pages under it.
final class SiteWithPagesModule<S extends PageSite> extends Module {
  /// Creates the module for the site made by [create].
  const SiteWithPagesModule(
    this.create, {
    this.extra = const [],
    this.withIndex = true,
  });

  /// Makes the site.
  final S Function(Injector) create;

  /// Pages besides `/`, as relative paths.
  final List<String> extra;

  /// Whether the `/` page is declared.
  final bool withIndex;

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<S>(create),
    // The hook of AdminSite and its subclasses; unused by the other sites.
    Singleton<AdminGuard>((_) => const AdminGuard(), dependsOn: const []),
    Pages.under<S>(
      (_) => [
        if (withIndex) homePage(const Component.text('index')),
        for (final path in extra)
          Page(path, build: (_) => const Component.text('page')),
      ],
    ),
  ];
}

/// Declares only the pages `/` and [extra] under the public site.
SiteWithPagesModule<PublicSite> publicSite({
  List<String> extra = const [],
  bool withIndex = true,
}) => SiteWithPagesModule<PublicSite>(
  PublicSite.new,
  extra: extra,
  withIndex: withIndex,
);

/// A site at `/admin2`, which shares a prefix with `/admin` but not a
/// segment.
final class Admin2Site extends PageSite {
  /// Creates the site.
  Admin2Site(super.injector);

  @override
  String get path => '/admin2';
}

/// A guarded site whose path is given by the test, valid or not.
final class PathSite extends AdminSite {
  /// Creates the site at [sitePath].
  PathSite(super.injector, this.sitePath);

  /// The path the site declares.
  final String sitePath;

  @override
  String get path => sitePath;
}
