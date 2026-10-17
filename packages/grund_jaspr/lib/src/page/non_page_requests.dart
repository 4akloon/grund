import 'package:grund_http/grund_http.dart';
import 'package:path/path.dart' as p;

import '../jaspr_config.dart';

/// Tells page requests from requests for files, so a path like
/// `/projects/logo.png` never reaches a page builder.
final class NonPageRequests {
  /// Decides by the `pageSuffixes` of [_config].
  NonPageRequests(this._config);

  final JasprConfig _config;

  /// Whether [uri] can be a page: its last segment has no extension, or one
  /// of the `pageSuffixes` (compared in lower case, without the dot).
  bool isPageRequest(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return true;
    final extension = p.extension(segments.last);
    return extension.isEmpty ||
        _config.pageSuffixes.contains(extension.substring(1).toLowerCase());
  }

  /// Answers 404 `file_not_found` for the file [uri].
  Never notFound(Uri uri) => throw NotFoundException(
    message: 'There is no file ${uri.path}.',
    code: 'file_not_found',
  );
}
