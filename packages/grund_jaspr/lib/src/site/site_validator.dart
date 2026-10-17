import '../error/page_declaration_error.dart';
import '../error/site_declaration_error.dart';
import 'page_snapshot.dart';
import 'pages_api.dart';
import 'site_api.dart';

/// Checks the rules that need every site and every pages declaration at
/// once, which no single declaration can see.
base class SiteValidator {
  /// Creates the validator.
  const SiteValidator();

  /// Throws the first [SiteDeclarationError] or [PageDeclarationError] that
  /// [snapshot] breaks.
  void check(PageSnapshot snapshot) {
    final sites = snapshot.sites;
    _checkTypes(sites);
    _checkPaths(sites);
    _checkIndexes(snapshot);
    _checkTerritories(snapshot);
  }

  void _checkTypes(List<SiteApi<Object?>> sites) {
    final seen = <Type>{};
    for (final api in sites) {
      if (!seen.add(api.siteType)) throw DuplicateSiteError(api.siteType);
      final actual = api.site.runtimeType;
      if (actual != api.siteType) {
        throw MismatchedSiteTypeError(expected: api.siteType, actual: actual);
      }
    }
  }

  void _checkPaths(List<SiteApi<Object?>> sites) {
    final seen = <String>{};
    for (final api in sites) {
      if (!seen.add(api.path)) throw DuplicateSitePathError(api.path);
    }
    for (final outer in sites) {
      for (final inner in sites) {
        if (_lies(inner.path, under: outer.path)) {
          throw NestedSitePathError(outer: outer.path, inner: inner.path);
        }
      }
    }
  }

  void _checkIndexes(PageSnapshot snapshot) {
    for (final site in snapshot.sites) {
      final hasIndex = snapshot.pages
          .where((api) => api.siteType == site.siteType)
          .any(
            (api) => api.pages.any((p) => api.fullPathOf(p) == _index(site)),
          );
      if (!hasIndex) throw MissingSiteIndexError(site.siteType);
    }
  }

  void _checkTerritories(PageSnapshot snapshot) {
    for (final api in snapshot.pages) {
      for (final page in api.pages) {
        final path = api.fullPathOf(page);
        _checkTerritory(snapshot.sites, api, path);
      }
    }
  }

  void _checkTerritory(
    List<SiteApi<Object?>> sites,
    PagesApi<Object?> api,
    String path,
  ) {
    for (final owner in sites) {
      if (owner.siteType == api.siteType || owner.path.isEmpty) continue;
      if (path == owner.path || _lies(path, under: owner.path)) {
        throw MisplacedPagePathError(
          path: path,
          siteType: api.siteType,
          owner: owner.siteType,
        );
      }
    }
  }

  // The root page of a site: the site path, or "/" for the root site.
  String _index(SiteApi<Object?> site) => site.path.isEmpty ? '/' : site.path;

  // Whether [path] lies strictly below [under]; the root site '' has no
  // territory.
  bool _lies(String path, {required String under}) =>
      under.isNotEmpty && path.startsWith('$under/');
}
