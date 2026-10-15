import 'dart:io';

import 'package:path/path.dart' as p;

/// The committed generated files of a fixture package: every
/// `*_module.g.dart` and `*_api.g.dart` under its `lib/`.
final class GoldenFiles {
  /// The golden files of the package rooted at [root].
  const GoldenFiles(this.root);

  /// Whether `GRUND_UPDATE_GOLDENS=1` asks for the files to be rewritten.
  static bool get updateRequested =>
      Platform.environment['GRUND_UPDATE_GOLDENS'] == '1';

  /// Absolute path of the package root.
  final String root;

  /// The committed files by package-relative path with `/` separators.
  Map<String, String> read() => {
    for (final file in _committed())
      p.posix.joinAll(p.split(p.relative(file.path, from: root))): file
          .readAsStringSync(),
  };

  /// Makes the committed files exactly [files]: writes them and deletes
  /// every other golden file.
  void write(Map<String, String> files) {
    for (final file in _committed()) {
      file.deleteSync();
    }
    for (final MapEntry(key: path, value: content) in files.entries) {
      File(p.joinAll([root, ...p.posix.split(path)]))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }
  }

  List<File> _committed() => [
    for (final entity in Directory(
      p.join(root, 'lib'),
    ).listSync(recursive: true))
      if (entity is File &&
          (entity.path.endsWith('_module.g.dart') ||
              entity.path.endsWith('_api.g.dart')))
        entity,
  ];
}
