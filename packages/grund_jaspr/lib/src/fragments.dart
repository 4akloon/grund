import 'package:jaspr/server.dart' hide Key;
import 'package:grund_http/grund_http.dart';

import 'client_script_removal.dart';
import 'error/jaspr_error.dart';
import 'page/component_rendering.dart';
import 'page/page_renderer.dart';

/// Answers a request with a piece of HTML instead of a whole page, for
/// htmx-style interactivity without client-side Dart.
///
/// ```dart
/// Route.post('/tasks/:id/done', (c) async {
///   final id = c.path.integer('id');
///   await _tasks.complete(id);
///   return Fragments.respond(c, TaskRow(_tasks.get(id)));
/// });
/// ```
///
/// The component is rendered under the same scope as a page (`context.call`
/// works), but without a document around it, without the live reload script
/// and without the client script of the application.
abstract final class Fragments {
  /// The response for [fragment] with [status], as `text/html` with
  /// `cache-control: private, no-cache`.
  ///
  /// A status the component set itself wins, as for a page. Throws
  /// [JasprSetupError] when the module that declares the calling API does
  /// not import `JasprModule`, and [PageRenderError] when Jaspr answers 500.
  static Future<HttpResponse> respond(
    HttpCtx c,
    Component fragment, {
    int status = 200,
  }) async {
    if (c.maybe<PageRenderer>() == null) {
      throw const JasprSetupError(
        'Fragments.respond needs the Jaspr services: import JasprModule '
        'into the module that declares this API.',
      );
    }
    final rendered = await ComponentRendering.render(
      c,
      fragment,
      status: status,
      standalone: true,
    );
    return ClientScriptRemoval.from(rendered);
  }
}
