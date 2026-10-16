import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';
import 'package:path/path.dart' as p;

import 'jaspr_config.dart';
import 'page_renderer.dart';
import 'static_files.dart';

/// The routes of the pages: `GET /` and `GET /*` (Jaspr's `HEAD` comes
/// with them), below every API route, since a literal or `:param` segment
/// wins over `*`.
///
/// A path that names a file of the static directory gets the file; a path
/// whose extension is not a page suffix is a 404 `file_not_found`; any
/// other path is a page rendered from [app].
final class JasprPages extends HttpApi {
  /// Serves the pages of [app] and the files of [config] in the module of
  /// [injector].
  JasprPages(
    super.injector, {
    required Component Function() app,
    JasprConfig config = const JasprConfig(),
  }) : _renderer = PageRenderer(app, liveReloadUrl: config.liveReloadUrl),
       _files = StaticFiles(config.staticDirectory),
       _pageSuffixes = config.pageSuffixes;

  final PageRenderer _renderer;
  final StaticFiles _files;
  final List<String> _pageSuffixes;

  @override
  List<Route> get routes => [Route.get('/', _serve), Route.get('/*', _serve)];

  Future<HttpResponse> _serve(HttpCtx c) async {
    final segments = c.request.uri.pathSegments;
    if (_files.find(segments) case final file?) return _files.respond(file);
    if (!_isPage(segments)) {
      throw NotFoundException(
        message: 'There is no file ${c.request.uri.path}.',
        code: 'file_not_found',
      );
    }
    return _renderer.render(c);
  }

  bool _isPage(List<String> segments) {
    if (segments.isEmpty) return true;
    final extension = p.extension(segments.last);
    return extension.isEmpty ||
        _pageSuffixes.contains(extension.substring(1).toLowerCase());
  }
}
