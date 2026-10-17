import 'package:grund_http/grund_http.dart';

import '../jaspr_config.dart';
import '../page/non_page_requests.dart';
import 'static_files.dart';

/// The routes of the static files: everything under `staticPath` and each
/// of the `rootFiles`.
///
/// It has no site hooks, so a guest gets the files of a guarded site's page.
final class StaticApi extends HttpApi {
  /// Serves [_files] for [_config] in the module of [injector].
  StaticApi(super.injector, this._config, this._files, this._nonPage);

  final JasprConfig _config;
  final StaticFiles _files;
  final NonPageRequests _nonPage;

  @override
  List<Route> get routes => [
    Route.get('${_config.staticPath}/*', _serveStatic),
    for (final file in _config.rootFiles) Route.get('/$file', _serveRoot),
  ];

  Future<HttpResponse> _serveStatic(HttpCtx c) {
    final prefix = _config.staticPath.split('/').length - 1;
    return _serve(c.request.uri, c.request.uri.pathSegments.skip(prefix));
  }

  Future<HttpResponse> _serveRoot(HttpCtx c) =>
      _serve(c.request.uri, c.request.uri.pathSegments);

  Future<HttpResponse> _serve(Uri uri, Iterable<String> segments) async {
    final file = _files.find(segments.toList());
    if (file == null) _nonPage.notFound(uri);
    return _files.respond(file);
  }
}
