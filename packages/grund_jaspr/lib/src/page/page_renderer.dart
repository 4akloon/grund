import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import '../error/jaspr_error.dart';
import '../grund_scope.dart';
import '../jaspr_request.dart';
import '../jaspr_response.dart';
import '../live_reload_script.dart';
import 'page_match.dart';

/// Renders one component under a [GrundScope], through Jaspr, into an
/// [HttpResponse].
final class PageRenderer {
  /// Renders pages; with [liveReloadUrl], an HTML page gets the live reload
  /// script.
  const PageRenderer({this.liveReloadUrl});

  /// Where the live reload script listens; `null` adds none.
  final Uri? liveReloadUrl;

  /// The response for [page] with [status], seen by [page] as the request
  /// [c] that matched [match]; throws [PageRenderError] when Jaspr answers
  /// 500.
  Future<HttpResponse> render(
    HttpCtx c,
    Component page, {
    int status = 200,
    PageMatch? match,
  }) async {
    final rendered = await renderComponent(
      GrundScope(httpContext: c, pageMatch: match, child: page),
      request: JasprRequest.from(c.request),
    );
    if (rendered.statusCode == StatusCode.internalServerError) {
      throw PageRenderError(method: c.request.method, path: c.request.uri.path);
    }
    final built = JasprResponse.from(rendered);
    // A status the component set itself (not Jaspr's default 200) wins.
    final response = built.status == StatusCode.ok
        ? HttpResponse(status, headers: built.headers, body: built.body)
        : built;
    final url = liveReloadUrl;
    return url == null ? response : LiveReloadScript.addTo(response, url);
  }
}
