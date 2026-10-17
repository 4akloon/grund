import 'dart:io';

import 'package:grund_http/grund_http.dart';
import 'package:path/path.dart' as p;

import '../content_types.dart';
import 'static_encodings.dart';
import 'static_validators.dart';

/// The files of a directory, served as they are.
///
/// A request path maps to a file only when every segment is a plain name:
/// not empty, not starting with `.` (so no `..`, no `.env`), without `/`,
/// `\`, `:` or control characters (a percent-encoded `%2F` or `%5C` arrives
/// decoded in a segment), and the file, with symbolic links resolved, lies
/// inside the directory.
final class StaticFiles {
  /// Serves [directory]; a relative path is resolved against the working
  /// directory. A directory that does not exist serves nothing.
  StaticFiles(String directory) : root = p.normalize(p.absolute(directory));

  /// The absolute directory.
  final String root;

  /// The file for the decoded path [segments], or `null` when there is no
  /// such regular file in [root].
  String? find(List<String> segments) {
    if (segments.isEmpty || !segments.every(_isPlainName)) return null;
    final candidate = p.joinAll([root, ...segments]);
    if (!p.isWithin(root, candidate)) return null;
    try {
      if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.file) {
        return null;
      }
      final file = File(candidate).resolveSymbolicLinksSync();
      final directory = Directory(root).resolveSymbolicLinksSync();
      return p.isWithin(directory, file) ? file : null;
    } on FileSystemException {
      // Gone or unreadable between the checks: not a file to serve.
      return null;
    }
  }

  /// The response for [file]: `304` without a body when [requestHeaders]
  /// show the client has it, otherwise `200` with its bytes and type.
  ///
  /// A precompressed sibling (`app.js.br`, `app.js.gz`) is sent instead
  /// when `accept-encoding` allows it (see [StaticEncodings.choose]), with
  /// `content-encoding` and the type of [file]; its `etag` and
  /// `last-modified` are its own, so a conditional request is answered
  /// against the variant sent. Every response carries `etag`,
  /// `last-modified`, `vary: accept-encoding`, `cache-control: no-cache`
  /// (the browser revalidates every time) and `x-content-type-options:
  /// nosniff` (the browser trusts the type, not the content).
  Future<HttpResponse> respond(
    String file, {
    required HeaderMap requestHeaders,
  }) async {
    final variant = StaticEncodings.choose(
      file,
      root: root,
      acceptEncoding: requestHeaders['accept-encoding'],
    );
    final stat = await File(variant.path).stat();
    final etag = StaticValidators.etag(stat, variant: variant.encoding ?? '');
    final headers = HeaderMap.of({
      'etag': etag,
      'last-modified': StaticValidators.lastModified(stat.modified),
      'vary': 'accept-encoding',
      'cache-control': 'no-cache',
      'x-content-type-options': 'nosniff',
    });
    if (StaticValidators.isNotModified(
      requestHeaders,
      etag: etag,
      modified: stat.modified,
    )) {
      return HttpResponse(304, headers: headers);
    }
    headers.set('content-type', ContentTypes.forPath(file));
    if (variant.encoding case final encoding?) {
      headers.set('content-encoding', encoding);
    }
    return HttpResponse.bytes(
      await File(variant.path).readAsBytes(),
      headers: headers,
    );
  }

  static bool _isPlainName(String segment) =>
      segment.isNotEmpty &&
      !segment.startsWith('.') &&
      !segment.codeUnits.any(_isForbidden);

  static bool _isForbidden(int unit) =>
      unit < 0x20 ||
      unit == 0x7f ||
      unit == 0x2f ||
      unit == 0x5c ||
      unit == 0x3a;
}
