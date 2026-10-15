import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The files of `lib/` of a package of this workspace (the golden fixture
/// `users_app`), read from this checkout.
abstract final class FixtureFiles {
  /// The files of [package]'s `lib/`, keyed by path relative to the package
  /// root with `/` separators (`lib/src/users.dart`). Generated files are
  /// included only when [generated] is set.
  static Future<Map<String, String>> of(
    String package, {
    bool generated = false,
  }) async {
    final uri = await Isolate.resolvePackageUri(Uri.parse('package:$package/'));
    if (uri == null) {
      throw StateError('$package is not in the test package config.');
    }
    final lib = Directory.fromUri(uri);
    return {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (_path(lib, file) case final path
            when generated || !_isGenerated(path))
          path: file.readAsStringSync(),
    };
  }

  static bool _isGenerated(String path) => path.endsWith('.g.dart');

  static String _path(Directory lib, File file) => p.posix.joinAll([
    'lib',
    ...p.split(p.relative(file.path, from: lib.path)),
  ]);
}
