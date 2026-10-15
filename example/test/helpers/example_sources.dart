import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The `lib/` of this example package, read from the checkout.
abstract final class ExampleSources {
  /// Whether [path] names a file the generator writes (`X_module.g.dart`,
  /// `X_api.g.dart`).
  static bool isGenerated(String path) =>
      path.endsWith('_module.g.dart') || path.endsWith('_api.g.dart');

  /// Every hand-written file of `lib/`, by path relative to the package
  /// root with `/` separators (`lib/src/tasks/task.dart`).
  static Future<Map<String, String>> sources() => _read(isGenerated: false);

  /// Every committed generated file of `lib/`, by the same kind of path.
  static Future<Map<String, String>> committedGenerated() =>
      _read(isGenerated: true);

  static Future<Map<String, String>> _read({required bool isGenerated}) async {
    final lib = await _lib();
    return {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (_path(lib, file) case final path
            when ExampleSources.isGenerated(path) == isGenerated)
          path: file.readAsStringSync(),
    };
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
