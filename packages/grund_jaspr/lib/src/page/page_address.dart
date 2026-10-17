/// Builds the URL path of a page pattern.
abstract final class PageAddress {
  /// [fullPattern] with every `:name` segment replaced by its value from
  /// [params]; every segment is percent-encoded, so a value never adds a
  /// segment.
  static String encodedPath(String fullPattern, Map<String, String> params) {
    if (fullPattern == '/') return '/';
    final segments = [
      for (final segment in fullPattern.substring(1).split('/'))
        Uri.encodeComponent(
          segment.startsWith(':')
              ? (params[segment.substring(1)] ?? segment)
              : segment,
        ),
    ];
    return '/${segments.join('/')}';
  }
}
