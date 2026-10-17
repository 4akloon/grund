import 'package:grund_http/grund_http.dart';
import 'package:path/path.dart' as p;

import 'trailing_slash.dart';

/// The permanent redirect of a request URL to its canonical spelling under
/// the [TrailingSlash] policy of a site.
abstract final class CanonicalRedirect {
  /// The 308 for a page request whose path is not canonical under [policy];
  /// `null` when it is, or when [policy] is [TrailingSlash.ignore].
  static HttpResponse? forPage(Uri uri, TrailingSlash policy) =>
      _redirect(uri, policy, hasSlash: policy == TrailingSlash.always);

  /// Like [forPage] for a file (an alternate, a site file, a sitemap): its
  /// canonical form never ends with a slash.
  static HttpResponse? forFile(Uri uri, TrailingSlash policy) =>
      _redirect(uri, policy, hasSlash: false);

  static HttpResponse? _redirect(
    Uri uri,
    TrailingSlash policy, {
    required bool hasSlash,
  }) {
    if (policy == TrailingSlash.ignore) return null;
    // Built from the raw path with the empty segments dropped, so the result
    // never starts with `//` and a `%2F` stays inside its segment.
    final segments = [
      for (final segment in uri.path.split('/'))
        if (segment.isNotEmpty) segment,
    ];
    final slash = hasSlash && !_hasExtension(segments);
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

  static bool _hasExtension(List<String> segments) =>
      segments.isNotEmpty && p.extension(segments.last).isNotEmpty;
}
