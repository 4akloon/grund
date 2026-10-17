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

  /// Answers a file request for [uri] (a last path segment with an extension
  /// outside `JasprConfig.pageSuffixes`) before the JSON 404, or returns
  /// `null`. A page-like path that matches no page never reaches it.
  ///
  /// It runs after the hooks of the site, on file requests below the site.
  /// The extensions of pages with their own `hooks.use` are not asked, so a
  /// page-level guard is never bypassed; a layer that needs to serve a
  /// variant of such a page does it through [respond] on the page route.
  Future<HttpResponse?> claim(HttpCtx c, Uri uri) async => null;
}
