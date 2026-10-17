import 'package:grund_http/grund_http.dart';
import 'package:path/path.dart' as p;

import '../jaspr_config.dart';
import 'page_extension.dart';

/// Tells page requests from requests for files, so a path like
/// `/projects/logo.png` never reaches a page builder.
final class NonPageRequests {
  /// Decides by the `pageSuffixes` of [_config].
  NonPageRequests(this._config);

  final JasprConfig _config;

  /// Whether [uri] can be a page: its last segment has no extension, or one
  /// of the `pageSuffixes` (compared in lower case, without the dot).
  ///
  /// A last segment with a dot, such as `v1.2` or `john.doe`, is a file
  /// request and answers 404 `file_not_found` unless its extension is a page
  /// suffix; the `staticPath` and the `rootFiles` are the only static URLs.
  bool isPageRequest(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return true;
    final extension = p.extension(segments.last);
    return extension.isEmpty ||
        _config.pageSuffixes.contains(extension.substring(1).toLowerCase());
  }

  /// Answers the request for the file [HttpCtx.request] with the first
  /// non-`null` `claim` of [extensions], or 404 `file_not_found` when none
  /// claims it.
  Future<HttpResponse> answer(
    HttpCtx c,
    Iterable<PageExtension> extensions,
  ) async {
    final uri = c.request.uri;
    for (final extension in extensions) {
      final response = await extension.claim(c, uri);
      if (response != null) return response;
    }
    notFound(uri);
  }

  /// Answers 404 `file_not_found` for the file [uri].
  Never notFound(Uri uri) => throw NotFoundException(
    message: 'There is no file ${uri.path}.',
    code: 'file_not_found',
  );
}
