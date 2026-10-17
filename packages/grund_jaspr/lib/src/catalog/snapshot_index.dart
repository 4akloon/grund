import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import '../page/page_match.dart';
import '../page/page_matcher.dart';
import '../page/site_page.dart';
import '../site/page_snapshot.dart';
import 'snapshot_pages.dart';

/// What the catalog reads from a snapshot: its pages, listed once, and the
/// matching of request URLs the way the running server does it (the static
/// layer and file requests are not pages).
///
/// The index is rebuilt when the snapshot is replaced, so every read of one
/// snapshot sees the same declarations and the user's page declarations run
/// once per snapshot.
final class SnapshotIndex {
  /// Creates the index for [_config].
  SnapshotIndex(this._config) : _nonPage = NonPageRequests(_config);

  final JasprConfig _config;
  final NonPageRequests _nonPage;

  PageSnapshot? _indexed;
  List<SitePage> _pages = const [];
  PageMatcher _matcher = PageMatcher(const []);

  /// Every page of [snapshot], sorted by path.
  List<SitePage> pages(PageSnapshot snapshot) {
    _load(snapshot);
    return _pages;
  }

  /// The pages of the site of exactly the type [siteType].
  List<SitePage> pagesOf(PageSnapshot snapshot, Type siteType) => [
    for (final page in pages(snapshot))
      if (page.site.runtimeType == siteType) page,
  ];

  /// The page of [snapshot] that serves [uri], or `null`.
  PageMatch? match(PageSnapshot snapshot, Uri uri) {
    final List<String> segments;
    try {
      // A malformed percent-encoding is a 400 of the server, not a page.
      if (!_nonPage.isPageRequest(uri)) return null;
      segments = [
        for (final segment in uri.pathSegments)
          if (segment.isNotEmpty) segment,
      ];
    } on FormatException {
      return null;
    }
    if (_isStatic(segments)) return null;
    _load(snapshot);
    return _matcher.match(segments);
  }

  // The server drops empty segments before routing, so [segments] has none.
  bool _isStatic(List<String> segments) {
    final prefix = _config.staticPath.substring(1).split('/');
    if (segments.length > prefix.length) {
      var underStatic = true;
      for (var i = 0; i < prefix.length; i++) {
        underStatic = underStatic && segments[i] == prefix[i];
      }
      if (underStatic) return true;
    }
    return segments.length == 1 && _config.rootFiles.contains(segments.single);
  }

  void _load(PageSnapshot snapshot) {
    if (identical(_indexed, snapshot)) return;
    final pages = SnapshotPages.all(snapshot);
    _matcher = PageMatcher(
      pages,
      sitePaths: [for (final api in snapshot.sites) api.path],
    );
    _pages = pages;
    _indexed = snapshot;
  }
}
