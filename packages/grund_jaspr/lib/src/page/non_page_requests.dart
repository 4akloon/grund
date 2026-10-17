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
  ///
  /// A last segment with a dot, such as `v1.2` or `john.doe`, is a file
  /// request and answers 404 `file_not_found` unless its extension is a page
  /// suffix; the `staticPath` and the `rootFiles` are the only static URLs.
  bool isPageRequest(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return true;
    return !isFileSegment(segments.last, _config.pageSuffixes);
  }

  /// Whether [segment] names a file: it has an extension that is not one of
  /// [pageSuffixes] (compared in lower case, without the dot).
  ///
  /// The one test of what is a file request; the canonical addresses of
  /// pages use it to never end in a spelling that would be one.
  static bool isFileSegment(String segment, List<String> pageSuffixes) {
    final extension = p.extension(segment);
    return extension.isNotEmpty &&
        !pageSuffixes.contains(extension.substring(1).toLowerCase());
  }

  /// Answers 404 `file_not_found` for the file [uri].
  Never notFound(Uri uri) => throw NotFoundException(
    message: 'There is no file ${uri.path}.',
    code: 'file_not_found',
  );
}
