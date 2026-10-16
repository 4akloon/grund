import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'grund_scope.dart';
import 'jaspr_error.dart';
import 'jaspr_request.dart';
import 'jaspr_response.dart';
import 'live_reload_script.dart';

/// Renders the page of one request: a new root component from [app] under
/// a [GrundScope], through Jaspr, into an [HttpResponse].
final class PageRenderer {
  /// Renders [app]; with [liveReloadUrl], an HTML page gets the live reload
  /// script.
  const PageRenderer(this.app, {this.liveReloadUrl});

  /// Builds the root component; called for every request, so a hot reload
  /// shows in the next page.
  final Component Function() app;

  /// Where the live reload script listens; `null` adds none.
  final Uri? liveReloadUrl;

  /// The page for [c]; throws [PageRenderError] when Jaspr answers 500.
  Future<HttpResponse> render(HttpCtx c) async {
    final rendered = await renderComponent(
      GrundScope(httpContext: c, child: app()),
      request: JasprRequest.from(c.request),
    );
    if (rendered.statusCode == StatusCode.internalServerError) {
      throw PageRenderError(method: c.request.method, path: c.request.uri.path);
    }
    final response = JasprResponse.from(rendered);
    final url = liveReloadUrl;
    return url == null ? response : LiveReloadScript.addTo(response, url);
  }
}
