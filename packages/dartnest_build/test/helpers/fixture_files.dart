import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The files of `lib/` of a package of this workspace (the generator's
/// fixtures `users_app` and `cases_app`), read from this checkout.
abstract final class FixtureFiles {
  /// The files of [package]'s `lib/` except its own generated library
  /// `lib/<package>.dartnest.dart`, keyed by path relative to the package
  /// root with `/` separators (`lib/src/users.dart`).
  static Future<Map<String, String>> of(String package) async {
    final uri = await Isolate.resolvePackageUri(Uri.parse('package:$package/'));
    if (uri == null) {
      throw StateError('$package is not in the test package config.');
    }
    final lib = Directory.fromUri(uri);
    final output = 'lib/$package.dartnest.dart';
    return {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (_path(lib, file) case final path when path != output)
          path: file.readAsStringSync(),
    };
  }

  /// The committed `lib/<package>.dartnest.dart` of [package].
  static Future<String> golden(String package) async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:$package/$package.dartnest.dart'),
    );
    if (uri == null) {
      throw StateError('$package is not in the test package config.');
    }
    return File.fromUri(uri).readAsStringSync();
  }

  static String _path(Directory lib, File file) => p.posix.joinAll([
    'lib',
    ...p.split(p.relative(file.path, from: lib.path)),
  ]);
}
