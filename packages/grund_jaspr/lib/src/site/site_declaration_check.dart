import '../error/site_declaration_error.dart';
import '../jaspr_config.dart';
import '../page/page_path.dart';
import 'page_site.dart';

/// Rejects a site declaration that contradicts the configuration.
abstract final class SiteDeclarationCheck {
  /// Throws [InvalidSitePathError] when the path of [site] is not `''` or
  /// `/segment[/segment]` of literals, lies on the `staticPath` of [config]
  /// or is a `rootFiles` entry, [InvalidSiteBaseUrlError] for a bad
  /// `baseUrl`, and [GuardedSiteSitemapError] (naming [siteType]) when the
  /// site has hooks and a sitemap.
  static void check(
    PageSite site, {
    required Type siteType,
    required JasprConfig config,
  }) {
    final path = site.path;
    PagePath.checkSitePath(path);
    if (config.rootFiles.any((file) => path == '/$file')) {
      throw InvalidSitePathError(
        path: path,
        reason: 'it is the root file "${path.substring(1)}"',
      );
    }
    if (path == config.staticPath || path.startsWith('${config.staticPath}/')) {
      throw InvalidSitePathError(
        path: path,
        reason: 'it is the static path "${config.staticPath}" or lies under it',
      );
    }
    _checkBaseUrl(site, siteType);
    if (site.use.isNotEmpty && site.baseUrl != null) {
      throw GuardedSiteSitemapError(siteType);
    }
  }

  static void _checkBaseUrl(PageSite site, Type siteType) {
    final url = site.baseUrl;
    if (url == null) return;
    final reason = switch (url) {
      Uri(scheme: != 'http' && != 'https') =>
        'the scheme must be http or https',
      Uri(host: '') => 'it has no host',
      Uri(path: != '' && != '/') => 'the path must be empty or "/"',
      Uri(hasQuery: true) => 'it must not have a query',
      Uri(hasFragment: true) => 'it must not have a fragment',
      Uri(userInfo: != '') => 'it must not have userinfo',
      _ => null,
    };
    if (reason != null) {
      throw InvalidSiteBaseUrlError(
        siteType: siteType,
        url: url,
        reason: reason,
      );
    }
  }
}
