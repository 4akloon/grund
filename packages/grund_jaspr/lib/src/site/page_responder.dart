import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart' hide Key;

import '../page/page.dart';
import '../page/page_match.dart';
import 'canonical_redirect.dart';
import 'page_site.dart';
import 'site_services.dart';

/// Builds the responses of the pages of a site and of its not-found page.
final class PageResponder {
  /// Creates the responder on [_services].
  const PageResponder(this._services);

  final SiteServices _services;

  /// The response for [match] of [page]: a redirect to the canonical spelling
  /// of the URL, a 404 for a file request, the rendered page, or the site's
  /// not-found page when the builder throws [NotFoundException].
  Future<HttpResponse> page(
    HttpCtx c, {
    required PageSite site,
    required Page page,
    required PageMatch match,
  }) async {
    final uri = c.request.uri;
    final redirect = CanonicalRedirect.forPage(uri, site.trailingSlash);
    if (redirect != null) return redirect;
    if (!_services.nonPage.isPageRequest(uri)) _services.nonPage.notFound(uri);
    final Component content;
    try {
      content = await page.build(c);
    } on NotFoundException {
      return notFound(c, site);
    }
    return _services.renderer.render(c, site.shell(content), match: match);
  }

  /// The not-found page of [site], in its shell, with status 404.
  Future<HttpResponse> notFound(HttpCtx c, PageSite site) => _services.renderer
      .render(c, site.shell(site.notFound()), status: StatusCode.notFound);
}
