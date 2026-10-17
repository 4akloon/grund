import '../error/site_declaration_error.dart';
import '../jaspr_config.dart';
import 'page_declaration_check.dart';
import 'page_site.dart';
import 'reserved_paths.dart';
import 'site_file.dart';

/// Rejects a site file that cannot be served.
abstract final class SiteFileCheck {
  /// Throws [InvalidSiteFileError] (naming [siteType]) for the first file of
  /// [site] whose path is not a plain literal path, whose media type is not
  /// `type/subtype` or whose URL the framework serves itself.
  static void check(
    PageSite site, {
    required Type siteType,
    required JasprConfig config,
  }) {
    for (final file in site.files) {
      final reason = _reasonFor(file, site, config);
      if (reason != null) {
        throw InvalidSiteFileError(
          siteType: siteType,
          path: file.path,
          reason: reason,
        );
      }
    }
  }

  static String? _reasonFor(SiteFile file, PageSite site, JasprConfig config) {
    final path = file.path;
    if (!path.startsWith('/')) return 'the path must start with "/"';
    if (path == '/') return 'the path must name a file, not the site root';
    if (path.contains(':') || path.contains('*')) {
      return 'the path must consist of literal segments';
    }
    if (path.substring(1).split('/').any((segment) => segment.isEmpty)) {
      return 'the path has an empty segment';
    }
    if (!PageDeclarationCheck.mediaTypePattern.hasMatch(file.mediaType)) {
      return 'the media type "${file.mediaType}" is not a lower case '
          'type/subtype';
    }
    return ReservedPaths.reasonFor(
      '${site.path}$path',
      sitePath: site.path,
      config: config,
    );
  }
}
