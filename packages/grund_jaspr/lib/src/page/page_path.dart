import '../error/page_declaration_error.dart';
import '../error/site_declaration_error.dart';

/// A parsed page path: literal segments and `:name` parameters.
final class PagePath {
  PagePath._(this._segments);

  final List<String> _segments;

  /// Parses [path] (`/`, `/about`, `/projects/:slug`).
  ///
  /// Throws [InvalidPagePathError] when the path does not start with `/`,
  /// has `*`, an empty segment or parameter name, or mixes a literal and
  /// `:` in one segment.
  static PagePath parse(String path) {
    if (!path.startsWith('/')) {
      throw InvalidPagePathError(path: path, reason: 'it must start with "/"');
    }
    if (path.contains('*')) {
      throw InvalidPagePathError(
        path: path,
        reason: 'wildcards ("*") are not supported',
      );
    }
    if (path == '/') return PagePath._(const []);
    final segments = path.substring(1).split('/');
    for (final segment in segments) {
      _checkSegment(path, segment);
    }
    return PagePath._(segments);
  }

  /// Checks a site path: `''` or `/segment[/segment]`, literals only, no
  /// trailing `/`.
  ///
  /// Throws [InvalidSitePathError] otherwise.
  static void checkSitePath(String path) {
    if (path.isEmpty) return;
    final reason = _siteReason(path);
    if (reason != null) throw InvalidSitePathError(path: path, reason: reason);
  }

  static String? _siteReason(String path) {
    if (!path.startsWith('/')) return 'it must start with "/"';
    if (path.endsWith('/')) return 'it must not end with "/"';
    if (path.contains('*')) return 'wildcards ("*") are not supported';
    for (final segment in path.substring(1).split('/')) {
      if (segment.isEmpty) return 'it has an empty segment';
      if (segment.contains(':')) return 'parameters (":") are not allowed';
    }
    return null;
  }

  static void _checkSegment(String path, String segment) {
    if (segment.isEmpty) {
      throw InvalidPagePathError(path: path, reason: 'it has an empty segment');
    }
    if (!segment.contains(':')) return;
    if (!segment.startsWith(':')) {
      throw InvalidPagePathError(
        path: path,
        reason: 'segment "$segment" mixes a literal and a parameter',
      );
    }
    final name = segment.substring(1);
    if (name.isEmpty || name.contains(':')) {
      throw InvalidPagePathError(
        path: path,
        reason: 'segment "$segment" has no valid parameter name',
      );
    }
  }

  /// The path in its canonical form (`/` for the root).
  String get normalized => _segments.isEmpty ? '/' : '/${_segments.join('/')}';

  /// The names of the parameters, in order.
  List<String> get paramNames => [
    for (final segment in _segments)
      if (segment.startsWith(':')) segment.substring(1),
  ];

  /// Whether the path has at least one parameter.
  bool get hasParams => _segments.any((segment) => segment.startsWith(':'));
}
