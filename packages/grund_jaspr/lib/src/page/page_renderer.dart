import 'package:grund_http/grund_http.dart';
import 'package:jaspr/jaspr.dart' show Component;

import '../live_reload_script.dart';
import 'component_rendering.dart';
import 'page_match.dart';

/// Renders one component under a `GrundScope`, through Jaspr, into an
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
  ///
  /// [status] applies unless the component set a non-200 status itself,
  /// which then wins. A component that sets 200 cannot be told apart from
  /// Jaspr's default, so [status] overrides it.
  Future<HttpResponse> render(
    HttpCtx c,
    Component page, {
    int status = 200,
    PageMatch? match,
  }) async {
    final response = await ComponentRendering.render(
      c,
      page,
      status: status,
      match: match,
    );
    final url = liveReloadUrl;
    return url == null ? response : LiveReloadScript.addTo(response, url);
  }
}
