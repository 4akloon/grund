import 'package:grund_http/grund_http.dart';

import 'page_match.dart';

/// A capability a page can opt into, such as an alternative representation
/// of the same address.
abstract base class PageExtension {
  /// Creates the extension.
  const PageExtension();

  /// Answers the request for the matched page instead of the page itself,
  /// or returns `null` to let the page render.
  Future<HttpResponse?> respond(HttpCtx c, PageMatch match) async => null;

  /// Answers a request for [uri] that matched no page, or returns `null`.
  Future<HttpResponse?> claim(HttpCtx c, Uri uri) async => null;
}
