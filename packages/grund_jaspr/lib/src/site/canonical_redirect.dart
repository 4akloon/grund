import 'package:grund_http/grund_http.dart';
import 'package:path/path.dart' as p;

import '../page/non_page_requests.dart';
import 'trailing_slash.dart';

/// The permanent redirect of a request URL to its canonical spelling under
/// the [TrailingSlash] policy of a site.
abstract final class CanonicalRedirect {
  /// The 308 for a page request whose path is not canonical under [policy];
  /// `null` when it is, or when [policy] is [TrailingSlash.ignore].
  ///
  /// A last segment that would be a file request without its slash (an
  /// extension that is not one of [pageSuffixes], such as `v1.2`) keeps the
  /// slash under every policy: the canonical address never leads to a file
  /// request.
  static HttpResponse? forPage(
    Uri uri,
    TrailingSlash policy, {
    required List<String> pageSuffixes,
  }) => _redirect(
    uri,
    policy,
    slashAfter: (last) =>
        NonPageRequests.isFileSegment(last, pageSuffixes) ||
        (policy == TrailingSlash.always && p.extension(last).isEmpty),
  );

  /// Like [forPage] for a file (an alternate, a site file, a sitemap): its
  /// canonical form never ends with a slash.
  static HttpResponse? forFile(Uri uri, TrailingSlash policy) =>
      _redirect(uri, policy, slashAfter: (_) => false);

  static HttpResponse? _redirect(
    Uri uri,
    TrailingSlash policy, {
    required bool Function(String lastSegment) slashAfter,
  }) {
    if (policy == TrailingSlash.ignore) return null;
    // Built from the raw path with the empty segments dropped, so the result
    // never starts with `//` and a `%2F` stays inside its segment.
    final segments = [
      for (final segment in uri.path.split('/'))
        if (segment.isNotEmpty) segment,
    ];
    final slash = segments.isNotEmpty && slashAfter(_lastSegment(uri));
    final canonical = segments.isEmpty
        ? '/'
        : '/${segments.join('/')}${slash ? '/' : ''}';
    if (canonical == uri.path) return null;
    final location = Uri(
      path: canonical,
      query: uri.hasQuery ? uri.query : null,
    );
    return HttpResponse(
      StatusCode.permanentRedirect,
      headers: HeaderMap.of({
        'location': location.toString(),
        'cache-control': 'max-age=3600',
      }),
    );
  }

  // Decoded, as the file request check sees it.
  static String _lastSegment(Uri uri) =>
      uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
}
