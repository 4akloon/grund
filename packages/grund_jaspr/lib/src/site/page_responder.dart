import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart' hide Key;

import '../page/page.dart';
import '../page/page_address.dart';
import '../page/page_alternate.dart';
import '../page/page_match.dart';
import 'alternate_negotiation.dart';
import 'canonical_redirect.dart';
import 'page_site.dart';
import 'site_services.dart';

/// Builds the responses of the pages of a site, of their alternates and of
/// its not-found page.
final class PageResponder {
  /// Creates the responder on [_services].
  const PageResponder(this._services);

  final SiteServices _services;

  /// The response for [match] of [page]: a 404 for a file request, a redirect
  /// to the canonical spelling of the URL, then, by the `Accept` header, an
  /// alternate or the rendered page, or the site's not-found page when the
  /// builder throws [NotFoundException].
  ///
  /// A page with alternates names `Accept` in `vary`, and its HTML links to
  /// them.
  Future<HttpResponse> page(
    HttpCtx c, {
    required PageSite site,
    required Page page,
    required PageMatch match,
    required bool isGuarded,
  }) async {
    final uri = c.request.uri;
    if (!_services.nonPage.isPageRequest(uri)) _services.nonPage.notFound(uri);
    final redirect = CanonicalRedirect.forPage(
      uri,
      site.trailingSlash,
      pageSuffixes: _services.config.pageSuffixes,
      isGuarded: isGuarded,
    );
    if (redirect != null) return redirect;
    if (page.alternates.isEmpty) return _htmlOrNotFound(c, site, page, match);
    final accept = AcceptHeader.parse(
      c.request.headers.all('accept').join(', '),
    );
    final alternate = AlternateNegotiation.choose(accept, page.alternates);
    final response = alternate == null
        ? await _htmlOrNotFound(c, site, page, match)
        : await _alternateOrNotFound(c, site, alternate, match);
    return response.withVary('accept');
  }

  /// The response for the own URL of [alternate] of [match]: a redirect to
  /// the canonical spelling, or its text with a `canonical` link to the page
  /// when the site has a `baseUrl`.
  Future<HttpResponse> alternate(
    HttpCtx c, {
    required PageSite site,
    required PageAlternate alternate,
    required PageMatch match,
    required bool isGuarded,
  }) async {
    final redirect = CanonicalRedirect.forFile(
      c.request.uri,
      site.trailingSlash,
      isGuarded: isGuarded,
    );
    if (redirect != null) return redirect;
    _requireAddressable(match);
    final response = await _alternateText(c, alternate, match);
    final url = match.url;
    if (url == null) return response;
    return response.mergeHeaders(
      HeaderMap.of({'link': '<$url>; rel="canonical"'}),
    );
  }

  /// The not-found page of [site], in its shell, with status 404.
  Future<HttpResponse> notFound(HttpCtx c, PageSite site) => _services.renderer
      .render(c, site.shell(site.notFound()), status: StatusCode.notFound);

  /// The text response of a generated file of [mediaType]: UTF-8, and
  /// `cache-control: private, no-cache` unless the request already set a
  /// `cache-control` through `c.response`.
  static HttpResponse text(HttpCtx c, String text, String mediaType) {
    final headers = HeaderMap.of({'content-type': '$mediaType; charset=utf-8'});
    if (!c.response.headers.contains('cache-control')) {
      headers.set('cache-control', 'private, no-cache');
    }
    return HttpResponse.text(text, headers: headers);
  }

  /// A parameter value of `.` or `..` has no address, so such a request names
  /// no page; checked before the builder runs. Only an alternate needs it: a
  /// dot segment of a page URL is removed by URI normalization before routing.
  static void _requireAddressable(PageMatch match) {
    for (final value in match.params.values) {
      if (value == '.' || value == '..') throw const NotFoundException();
    }
  }

  Future<HttpResponse> _alternateText(
    HttpCtx c,
    PageAlternate alternate,
    PageMatch match,
  ) async => text(c, await alternate.build(c, match), alternate.mediaType);

  Future<HttpResponse> _alternateOrNotFound(
    HttpCtx c,
    PageSite site,
    PageAlternate alternate,
    PageMatch match,
  ) async {
    try {
      return await _alternateText(c, alternate, match);
    } on NotFoundException {
      return notFound(c, site);
    }
  }

  Future<HttpResponse> _htmlOrNotFound(
    HttpCtx c,
    PageSite site,
    Page page,
    PageMatch match,
  ) async {
    final Component content;
    try {
      content = await page.build(c);
    } on NotFoundException {
      return notFound(c, site);
    }
    final html = await _services.renderer.render(
      c,
      site.shell(content),
      match: match,
    );
    return html.mergeHeaders(_alternateLinks(site, page, match));
  }

  HeaderMap _alternateLinks(PageSite site, Page page, PageMatch match) {
    final links = HeaderMap();
    for (final alternate in page.alternates) {
      final path = PageAddress.alternatePathOf(
        site.path,
        page.path,
        match.params,
        alternate.suffix,
      );
      final target = site.baseUrl?.resolve(path) ?? Uri(path: path);
      links.add(
        'link',
        '<$target>; rel="alternate"; type="${alternate.mediaType}"',
      );
    }
    return links;
  }
}
