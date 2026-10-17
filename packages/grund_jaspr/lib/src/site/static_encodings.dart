import 'dart:io';

import 'package:path/path.dart' as p;

/// The file to send for a request: [path] and the content [encoding] of
/// that file (`br`, `gzip`), or `null` for the requested file itself.
typedef StaticVariant = ({String path, String? encoding});

/// Chooses between a static file and its precompressed siblings
/// (`app.js.br`, `app.js.gz`) by the `Accept-Encoding` of the request.
abstract final class StaticEncodings {
  /// Content codings that have a sibling suffix, in order of preference
  /// when their qualities are equal.
  static const _suffixes = {'br': '.br', 'gzip': '.gz'};

  /// The variant of [file] (inside [root]) to send for [acceptEncoding].
  ///
  /// The accepted coding with the highest quality wins, `br` before `gzip`
  /// on a tie; `q=0` forbids a coding. A sibling counts only when it is a
  /// regular file inside [root] (symbolic links resolved) and not older
  /// than [file]; otherwise the next coding, then [file], is used. A file
  /// that itself ends in `.br` or `.gz` has no variants.
  static StaticVariant choose(
    String file, {
    required String root,
    String? acceptEncoding,
  }) {
    final original = (path: file, encoding: null as String?);
    if (acceptEncoding == null || _suffixes.values.any(file.endsWith)) {
      return original;
    }
    final qualities = _parse(acceptEncoding);
    final accepted = [
      for (final coding in _suffixes.keys)
        if (_quality(qualities, coding) > 0) coding,
    ]..sort((a, b) => _quality(qualities, b).compareTo(_quality(qualities, a)));
    for (final coding in accepted) {
      final sibling = file + _suffixes[coding]!;
      if (_isUsable(sibling, original: file, root: root)) {
        return (path: sibling, encoding: coding);
      }
    }
    return original;
  }

  static Map<String, double> _parse(String header) => {
    for (final item in header.split(','))
      if (item.split(';') case [final name, ...final parameters])
        name.trim().toLowerCase(): _qualityOf(parameters),
  };

  static double _qualityOf(List<String> parameters) {
    for (final parameter in parameters) {
      final pair = parameter.split('=');
      if (pair.length == 2 && pair[0].trim().toLowerCase() == 'q') {
        return double.tryParse(pair[1].trim()) ?? 0;
      }
    }
    return 1;
  }

  /// An explicit entry beats `*`; a coding that is not listed is refused.
  static double _quality(Map<String, double> qualities, String coding) =>
      qualities[coding] ?? qualities['*'] ?? 0;

  static bool _isUsable(
    String sibling, {
    required String original,
    required String root,
  }) {
    try {
      if (FileSystemEntity.typeSync(sibling) != FileSystemEntityType.file) {
        return false;
      }
      final resolved = File(sibling).resolveSymbolicLinksSync();
      final directory = Directory(root).resolveSymbolicLinksSync();
      return p.isWithin(directory, resolved) &&
          !File(resolved)
              .statSync()
              .modified
              .isBefore(File(original).statSync().modified);
    } on FileSystemException {
      // Gone or unreadable between the checks: not a sibling to serve.
      return false;
    }
  }
}
