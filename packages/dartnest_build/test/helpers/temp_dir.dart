import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fresh directory under the system temp directory, deleted when the
/// test that created it ends.
final class TempDir {
  TempDir._(this.path);

  /// Creates the directory and registers its deletion with [addTearDown].
  factory TempDir.create() {
    final directory = Directory.systemTemp.createTempSync('dartnest_build_');
    final temp = TempDir._(directory.resolveSymbolicLinksSync());
    addTearDown(temp._delete);
    return temp;
  }

  /// Absolute path of the directory, symbolic links resolved.
  final String path;

  /// The absolute path of [relative] (with `/` separators) in the directory.
  String resolve(String relative) => p.joinAll([path, ...relative.split('/')]);

  /// Writes [content] to [relative], creating parent directories; returns
  /// the absolute path.
  String write(String relative, String content) {
    final file = File(resolve(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  /// The content of [relative].
  String read(String relative) => File(resolve(relative)).readAsStringSync();

  /// Whether a file exists at [relative].
  bool exists(String relative) => File(resolve(relative)).existsSync();

  void _delete() {
    final directory = Directory(path);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
