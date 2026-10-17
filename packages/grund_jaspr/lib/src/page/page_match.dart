import 'page_address.dart';
import 'page_alternate.dart';
import 'page_meta.dart';
import 'site_page.dart';

/// A page that a request matched, with the values of its path parameters.
final class PageMatch {
  /// Creates the match.
  const PageMatch({required this.page, this.params = const {}});

  /// The matched page.
  final SitePage page;

  /// The path parameters by name.
  final Map<String, String> params;

  /// The title, navigation and sitemap settings of the matched page.
  PageMeta get meta => page.page.meta;

  /// The canonical path of the page with its parameter values:
  /// percent-encoded segments, spelled by the `trailingSlash` of the site.
  ///
  /// Throws [ArgumentError] when [params] lacks a value for a path parameter
  /// or has an empty, `.` or `..` value.
  String get path =>
      PageAddress.pathOf(page.path, params, page.site.trailingSlash);

  /// [path] on the `baseUrl` of the site; `null` when the site has none.
  Uri? get url => page.site.baseUrl?.resolve(path);

  /// The path of the alternate of [mediaType] of this page, with its
  /// parameter values.
  ///
  /// Throws [ArgumentError] when the page has no such alternate, or as
  /// [path] does for unusable parameters.
  String alternatePath(String mediaType) {
    final alternate = _alternateOf(mediaType);
    return PageAddress.alternatePathOf(
      page.site.path,
      page.page.path,
      params,
      alternate.suffix,
    );
  }

  PageAlternate _alternateOf(String mediaType) {
    for (final alternate in page.page.alternates) {
      if (alternate.mediaType == mediaType) return alternate;
    }
    throw ArgumentError.value(
      mediaType,
      'mediaType',
      'the page ${page.path} has no such alternate',
    );
  }
}
