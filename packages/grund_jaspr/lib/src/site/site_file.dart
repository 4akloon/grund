import 'dart:async';

import 'package:grund_http/grund_http.dart';

/// Builds the text of a site file.
typedef SiteFileBuilder = FutureOr<String> Function(HttpCtx c);

/// A generated text file at a fixed path of a site, such as `/robots.txt`.
final class SiteFile {
  /// Creates the file served at [path] (relative to the site) as
  /// [mediaType] in UTF-8.
  const SiteFile(this.path, {required this.mediaType, required this.build});

  /// The path relative to the site: `/` and literal segments, such as
  /// `/robots.txt`.
  final String path;

  /// The media type, `type/subtype` in lower case; the response adds
  /// `charset=utf-8`.
  final String mediaType;

  /// Builds the text of the file for a request.
  final SiteFileBuilder build;
}
