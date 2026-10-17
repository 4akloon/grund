import '../error/page_declaration_error.dart';
import '../jaspr_config.dart';
import '../page/page.dart';
import '../page/page_address.dart';
import '../page/page_alternate.dart';
import '../page/page_path.dart';
import 'page_site.dart';
import 'reserved_paths.dart';

/// Rejects a page declaration that contradicts the site or the framework.
abstract final class PageDeclarationCheck {
  /// What a lower case `type/subtype` looks like.
  static final mediaTypePattern = RegExp(
    r"^[!#$%&'+.^_`|~0-9a-z-]+/[!#$%&'+.^_`|~0-9a-z-]+$",
  );
  static final _suffix = RegExp(r'^(\.[a-z0-9]+)+$');

  /// Throws [ReservedPagePathError] when [page] at [fullPath] would take a
  /// URL the framework serves, [UnusedPageEntriesError] when it lists
  /// sitemap entries without parameters, [UndecidedPageSitemapError]
  /// when a parameterised page of a site with a sitemap does not say how it
  /// appears in it, [InvalidPageAlternateError] for an alternate that cannot
  /// be served and [MissingPageAlternateError] for one the site requires.
  static void check(
    Page page, {
    required PageSite site,
    required String fullPath,
    required JasprConfig config,
  }) {
    final reason = ReservedPaths.reasonFor(
      fullPath,
      sitePath: site.path,
      config: config,
    );
    if (reason != null) {
      throw ReservedPagePathError(path: fullPath, reason: reason);
    }
    final entries = page.meta.sitemap.entries;
    final hasParams = PagePath.parse(page.path).hasParams;
    if (!hasParams && entries != null) throw UnusedPageEntriesError(fullPath);
    final decided = entries != null || page.meta.sitemap.included == false;
    if (hasParams && site.baseUrl != null && !decided) {
      throw UndecidedPageSitemapError(fullPath);
    }
    _checkAlternates(page, site, fullPath, config);
  }

  static void _checkAlternates(
    Page page,
    PageSite site,
    String fullPath,
    JasprConfig config,
  ) {
    final types = <String>{};
    final suffixes = <String>{};
    for (final alternate in page.alternates) {
      var reason = _reasonFor(alternate, page, site, config);
      if (reason == null && !types.add(alternate.mediaType)) {
        reason = 'the page already has an alternate of this type';
      }
      if (reason == null && !suffixes.add(alternate.suffix)) {
        reason =
            'the page already has an alternate with the suffix '
            '"${alternate.suffix}"';
      }
      if (reason == null) continue;
      throw InvalidPageAlternateError(
        path: fullPath,
        mediaType: alternate.mediaType,
        reason: reason,
      );
    }
    for (final required in site.requiredAlternates) {
      if (!types.contains(required)) {
        throw MissingPageAlternateError(path: fullPath, mediaType: required);
      }
    }
  }

  static String? _reasonFor(
    PageAlternate alternate,
    Page page,
    PageSite site,
    JasprConfig config,
  ) {
    final type = alternate.mediaType;
    if (type.contains(';')) return 'a media type has no parameters';
    if (type.contains('*')) return 'a media type has no wildcards';
    if (!mediaTypePattern.hasMatch(type)) {
      return 'a media type is "type/subtype" in lower case';
    }
    if (type == 'text/html') return 'text/html is the page itself';
    final suffix = alternate.suffix;
    if (!_suffix.hasMatch(suffix)) {
      return 'a suffix is one or more ".lowercase" extensions, such as ".md"';
    }
    final extension = suffix.substring(suffix.lastIndexOf('.') + 1);
    if (config.pageSuffixes.contains(extension)) {
      return 'the extension ".$extension" is in pageSuffixes, where a '
          'request is taken for a file';
    }
    final pattern = PageAddress.alternatePatternOf(page.path, suffix);
    final reserved = ReservedPaths.reasonFor(
      '${site.path}$pattern',
      sitePath: site.path,
      config: config,
    );
    return reserved == null ? null : 'its URL is reserved: $reserved';
  }
}
