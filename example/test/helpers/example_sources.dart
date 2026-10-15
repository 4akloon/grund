import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The `lib/` of this example package, read from the checkout.
abstract final class ExampleSources {
  /// The generated library the CLI writes, relative to the package root.
  static const generatedLibrary = 'lib/tasks_api.grund.dart';

  /// Every file of `lib/` except [generatedLibrary], by path relative to
  /// the package root with `/` separators (`lib/src/tasks/task.dart`).
  static Future<Map<String, String>> files() async {
    final lib = await _lib();
    return {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (_path(lib, file) case final path when path != generatedLibrary)
          path: file.readAsStringSync(),
    };
  }

  /// The committed [generatedLibrary].
  static Future<String> committedLibrary() async {
    final lib = await _lib();
    return File(p.join(lib.parent.path, generatedLibrary)).readAsStringSync();
  }

  static Future<Directory> _lib() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:tasks_api/'),
    );
    if (uri == null) {
      throw StateError('tasks_api is not in the package config.');
    }
    return Directory.fromUri(uri);
  }

  static String _path(Directory lib, File file) => p.posix.joinAll([
    'lib',
    ...p.split(p.relative(file.path, from: lib.path)),
  ]);
}
