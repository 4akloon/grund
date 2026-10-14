import 'dart:io';

import 'package:dartnest_cli/src/package/package_root.dart';

import 'temp_dir.dart';
import 'workspace_package_config.dart';

/// A package in a [TempDir] that resolves against this workspace: a
/// `pubspec.yaml` named [name], a package config, an empty `lib/` and the
/// given files.
final class TempPackage {
  TempPackage._(this.name, this.dir);

  /// Creates the package with [files] (relative path → content).
  static Future<TempPackage> create(
    String name, [
    Map<String, String> files = const {},
  ]) async {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: $name\nenvironment:\n  sdk: ^3.8.0\n');
    Directory(dir.resolve('lib')).createSync();
    await WorkspacePackageConfig.write(dir.path, name);
    files.forEach(dir.write);
    return TempPackage._(name, dir);
  }

  /// The package name.
  final String name;

  /// The package directory.
  final TempDir dir;

  /// The package as the CLI opens it.
  PackageRoot get root => PackageRoot.open(dir.path);
}
