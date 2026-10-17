import 'package:path/path.dart' as p;

import '../site/trailing_slash.dart';
import 'non_page_requests.dart';

/// Builds the URL path of a page pattern.
abstract final class PageAddress {
  /// The concrete path of [fullPattern] with every `:name` segment replaced
  /// by its value from [params], spelled by [policy].
  ///
  /// Every segment is percent-encoded, so a value never adds a segment. Under
  /// [TrailingSlash.always] a slash ends every path but the root and one whose
  /// last segment has an extension. A last segment that would be a file
  /// request without the slash (an extension that is not one of
  /// [pageSuffixes], such as `v1.2`) keeps it under every policy. Throws
  /// [ArgumentError] naming the parameter when a value is missing, empty, `.`
  /// or `..`.
  static String pathOf(
    String fullPattern,
    Map<String, String> params,
    TrailingSlash policy, {
    required List<String> pageSuffixes,
  }) {
    if (fullPattern == '/') return '/';
    final raw = _segmentsOf(fullPattern, params);
    final slash =
        NonPageRequests.isFileSegment(raw.last, pageSuffixes) ||
        (policy == TrailingSlash.always && p.extension(raw.last).isEmpty);
    return '/${raw.map(Uri.encodeComponent).join('/')}${slash ? '/' : ''}';
  }

  /// The concrete path of an alternate of the page at [pagePath] of the site
  /// at [sitePath]: the page path (`/index` for a root page) plus [suffix],
  /// without a trailing slash.
  static String alternatePathOf(
    String sitePath,
    String pagePath,
    Map<String, String> params,
    String suffix,
  ) {
    final base = pagePath == '/' ? '$sitePath/index' : '$sitePath$pagePath';
    final raw = _segmentsOf(base, params);
    return '/${raw.map(Uri.encodeComponent).join('/')}$suffix';
  }

  /// The route pattern of an alternate, relative to its site: `/index` plus
  /// [suffix] for the root page, else [pagePath] plus [suffix].
  static String alternatePatternOf(String pagePath, String suffix) =>
      pagePath == '/' ? '/index$suffix' : '$pagePath$suffix';

  static List<String> _segmentsOf(
    String fullPattern,
    Map<String, String> params,
  ) => [
    for (final segment in fullPattern.substring(1).split('/'))
      segment.startsWith(':')
          ? _valueOf(segment.substring(1), params)
          : segment,
  ];

  static String _valueOf(String name, Map<String, String> params) {
    final value = params[name];
    if (value == null || value.isEmpty || value == '.' || value == '..') {
      throw ArgumentError.value(
        value,
        name,
        'is not a usable value for the path parameter "$name"',
      );
    }
    return value;
  }
}
