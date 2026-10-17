import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import '../error/jaspr_error.dart';
import '../grund_scope.dart';
import '../jaspr_request.dart';
import '../jaspr_response.dart';
import 'page_match.dart';

/// Renders one component under a [GrundScope], through Jaspr, into an
/// [HttpResponse]; shared by pages and HTML fragments.
abstract final class ComponentRendering {
  /// The response for [component] with [status], seen by [component] as the
  /// request [c] that matched [match]; throws [PageRenderError] when Jaspr
  /// answers 500.
  ///
  /// [status] applies unless the component set a non-200 status itself,
  /// which then wins. A component that sets 200 cannot be told apart from
  /// Jaspr's default, so [status] overrides it. With [standalone] Jaspr
  /// renders the component alone, without a document around it.
  static Future<HttpResponse> render(
    HttpCtx c,
    Component component, {
    int status = 200,
    PageMatch? match,
    bool standalone = false,
  }) async {
    final rendered = await renderComponent(
      GrundScope(httpContext: c, pageMatch: match, child: component),
      request: JasprRequest.from(c.request),
      standalone: standalone,
    );
    if (rendered.statusCode == StatusCode.internalServerError) {
      throw PageRenderError(method: c.request.method, path: c.request.uri.path);
    }
    final built = JasprResponse.from(rendered);
    // A status the component set itself (not Jaspr's default 200) wins.
    return built.status == StatusCode.ok
        ? HttpResponse(status, headers: built.headers, body: built.body)
        : built;
  }
}
