import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import '../page/page_match.dart';
import '../page/page_matcher.dart';
import '../site/page_snapshot.dart';
import 'snapshot_pages.dart';

/// Matches request URLs against the pages of a snapshot the way the
/// running server does: the static layer and file requests are not pages.
final class SnapshotMatcher {
  /// Creates the matcher for [_config].
  SnapshotMatcher(this._config) : _nonPage = NonPageRequests(_config);

  final JasprConfig _config;
  final NonPageRequests _nonPage;

  PageSnapshot? _indexed;
  PageMatcher? _matcher;

  /// The page of [snapshot] that serves [uri], or `null`.
  PageMatch? match(PageSnapshot snapshot, Uri uri) {
    final List<String> segments;
    try {
      // A malformed percent-encoding is a 400 of the server, not a page.
      if (!_nonPage.isPageRequest(uri)) return null;
      segments = uri.pathSegments;
    } on FormatException {
      return null;
    }
    if (_isStatic(segments)) return null;
    return _matcherFor(snapshot).match(segments);
  }

  bool _isStatic(List<String> segments) {
    final prefix = _config.staticPath.substring(1).split('/');
    final underStatic =
        segments.length > prefix.length &&
        [for (var i = 0; i < prefix.length; i++) segments[i]].join('/') ==
            prefix.join('/');
    return underStatic ||
        (segments.length == 1 && _config.rootFiles.contains(segments.single));
  }

  PageMatcher _matcherFor(PageSnapshot snapshot) {
    final cached = _matcher;
    if (cached != null && identical(_indexed, snapshot)) return cached;
    final matcher = PageMatcher(
      SnapshotPages.all(snapshot),
      sitePaths: [for (final api in snapshot.sites) api.path],
    );
    _indexed = snapshot;
    return _matcher = matcher;
  }
}
