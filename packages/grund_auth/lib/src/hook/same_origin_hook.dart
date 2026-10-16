import 'package:grund_http/grund_http.dart';

/// Refuses an unsafe request (not `GET`, `HEAD` or `OPTIONS`) that a
/// browser sent from another site: a 403 `cross_site_request`.
///
/// A request is cross-site when its `sec-fetch-site` is neither
/// `same-origin` nor `none`, or when its `origin` does not name the `host`
/// it was sent to. A request without these headers (not from a browser:
/// curl, another server) passes. `SessionHook` does the same check when
/// `SessionConfig.sameOrigin` is on; use this hook alone for an
/// application without sessions.
///
/// A request with more than one `origin` header is refused. Only the
/// host and port of `origin` are compared, not its scheme: the scheme the
/// browser used is not reliably known behind a TLS-terminating proxy.
/// There is no `referer` fallback by design.
///
/// Behind a proxy that rewrites `host`, `origin` no longer matches; forward
/// the original `host`.
final class SameOriginHook extends HttpHook {
  /// Creates the hook.
  const SameOriginHook();

  static const _safeMethods = {'GET', 'HEAD', 'OPTIONS'};

  @override
  void before(HttpCtx c) {
    final request = c.request;
    if (_safeMethods.contains(request.method)) return;
    final site = request.headers['sec-fetch-site'];
    if (site != null && site != 'same-origin' && site != 'none') {
      throw _refused('sec-fetch-site is $site');
    }
    final origins = request.headers.all('origin');
    if (origins.length > 1) throw _refused('more than one origin header');
    final origin = request.headers['origin'];
    if (origin != null && !_namesHost(origin, request.headers['host'])) {
      throw _refused('origin $origin is not the host');
    }
  }

  static bool _namesHost(String origin, String? host) {
    final uri = Uri.tryParse(origin);
    if (host == null || uri == null || !uri.hasAuthority) return false;
    final name = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final authority = uri.hasPort ? '$name:${uri.port}' : name;
    return authority.toLowerCase() == host.toLowerCase();
  }

  static ForbiddenException _refused(String why) => ForbiddenException(
    message: 'Cross-site request refused: $why.',
    code: 'cross_site_request',
  );
}
