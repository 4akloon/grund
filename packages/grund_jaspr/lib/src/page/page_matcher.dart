import 'page_match.dart';
import 'page_path.dart';
import 'site_page.dart';

/// Finds the page for a request path with the rules of the HTTP router:
/// a literal segment beats a `:param`, a failed branch is left for the
/// next, empty segments are dropped and the case matters.
///
/// A site path also claims everything below it (the site's own not found
/// page), as the router's `/*` route does, so a request such as
/// `/admin/x` matches no page of another site's `/:slug/x`.
final class PageMatcher {
  /// Indexes [pages]; [sitePaths] are the paths of all sites (`''` for the
  /// root site).
  PageMatcher(
    Iterable<SitePage> pages, {
    Iterable<String> sitePaths = const [],
  }) {
    for (final page in pages) {
      _insert(page);
    }
    for (final path in sitePaths) {
      _nodeFor(_split(path)).claimsRest = true;
    }
  }

  final _Node _root = _Node();

  /// The page for the decoded [segments] and its parameters, or `null`
  /// where no page would be served.
  PageMatch? match(List<String> segments) {
    final path = [
      for (final segment in segments)
        if (segment.isNotEmpty) segment,
    ];
    final found = _visit(_root, path, 0, []);
    final page = found?.page;
    if (found == null || page == null) return null;
    return PageMatch(
      page: page,
      params: Map.fromIterables(found.names, found.values),
    );
  }

  void _insert(SitePage page) {
    final pattern = PagePath.parse(page.path);
    final node = _nodeFor(_split(pattern.normalized));
    node.page ??= page;
    node.names = pattern.paramNames;
  }

  _Node _nodeFor(List<String> segments) {
    var node = _root;
    for (final segment in segments) {
      node = segment.startsWith(':')
          ? node.param ??= _Node()
          : node.literals.putIfAbsent(segment, _Node.new);
    }
    return node;
  }

  static List<String> _split(String path) => [
    for (final segment in path.split('/'))
      if (segment.isNotEmpty) segment,
  ];

  _Found? _visit(_Node node, List<String> path, int index, List<String> taken) {
    if (index == path.length) {
      final page = node.page;
      return page == null ? null : _Found(page, node.names, [...taken]);
    }
    final segment = path[index];
    final literal = node.literals[segment];
    final viaLiteral = literal == null
        ? null
        : _visit(literal, path, index + 1, taken);
    if (viaLiteral != null) return viaLiteral;
    final param = node.param;
    if (param != null) {
      taken.add(segment);
      final viaParam = _visit(param, path, index + 1, taken);
      taken.removeLast();
      if (viaParam != null) return viaParam;
    }
    return node.claimsRest ? const _Found(null, [], []) : null;
  }
}

final class _Node {
  final Map<String, _Node> literals = {};
  _Node? param;
  SitePage? page;
  List<String> names = const [];
  bool claimsRest = false;
}

final class _Found {
  const _Found(this.page, this.names, this.values);

  final SitePage? page;
  final List<String> names;
  final List<String> values;
}
