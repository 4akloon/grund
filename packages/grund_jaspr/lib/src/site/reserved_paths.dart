import '../jaspr_config.dart';

/// Tells which URLs the framework serves itself and a page may not take.
abstract final class ReservedPaths {
  /// Why [fullPath] of a page of the site at [sitePath] is taken by the
  /// framework, or `null` when the path is free.
  static String? reasonFor(
    String fullPath, {
    required String sitePath,
    required JasprConfig config,
  }) {
    final staticPath = config.staticPath;
    if (fullPath == staticPath || fullPath.startsWith('$staticPath/')) {
      return 'static files are served under "$staticPath"';
    }
    if (fullPath == '$sitePath/sitemap.xml' ||
        fullPath.startsWith('$sitePath/sitemap/')) {
      return 'the sitemap of the site is served at "$sitePath/sitemap.xml" '
          'and under "$sitePath/sitemap/"';
    }
    for (final file in config.rootFiles) {
      if (fullPath == '/$file') {
        return 'the static file "$file" is served at the root';
      }
    }
    return null;
  }
}
