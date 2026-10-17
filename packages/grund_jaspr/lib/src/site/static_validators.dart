import 'dart:io' as io;

import 'package:grund_http/grund_http.dart';

/// The validators of a static file (`ETag`, `Last-Modified`) and the
/// decision whether a conditional request still holds.
abstract final class StaticValidators {
  /// The weak tag of a file with [stat]: its size and modification time in
  /// milliseconds, both in hex, plus the [variant] (such as `br`) of a
  /// stored encoding.
  static String etag(io.FileStat stat, {String variant = ''}) {
    final size = stat.size.toRadixString(16);
    final modified = stat.modified.millisecondsSinceEpoch.toRadixString(16);
    final suffix = variant.isEmpty ? '' : '-$variant';
    return 'W/"$size-$modified$suffix"';
  }

  /// [modified] as an HTTP date.
  static String lastModified(DateTime modified) =>
      io.HttpDate.format(modified.toUtc());

  /// Whether the request headers show that the client already has the
  /// representation with [etag] and [modified].
  ///
  /// `if-none-match` decides alone when present; otherwise
  /// `if-modified-since` is compared to the second, and an unparsable date
  /// means the file is sent.
  static bool isNotModified(
    HeaderMap request, {
    required String etag,
    required DateTime modified,
  }) {
    final noneMatch = request['if-none-match'];
    if (noneMatch != null) return _matches(noneMatch, etag);
    final since = request['if-modified-since'];
    if (since == null) return false;
    try {
      final date = io.HttpDate.parse(since);
      return modified.millisecondsSinceEpoch ~/ 1000 <=
          date.millisecondsSinceEpoch ~/ 1000;
    } on io.HttpException {
      // A malformed date from the client is not a condition: send the file.
      return false;
    }
  }

  static bool _matches(String header, String etag) {
    if (header.trim() == '*') return true;
    final own = _opaque(etag);
    return header.split(',').any((tag) => _opaque(tag) == own);
  }

  static String _opaque(String tag) {
    final trimmed = tag.trim();
    return trimmed.startsWith('W/') ? trimmed.substring(2) : trimmed;
  }
}
