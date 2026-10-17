import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:path/path.dart' as p;

import 'temp_dir.dart';
import 'workspace_package_config.dart';

/// Runs the CLI's generation once over a fresh package outside the
/// workspace, resolved against this checkout without `pub get`.
abstract final class CliGeneration {
  /// Generates package [name] made of [files] (path relative to the
  /// package root → content). Returns the CLI's report and the generated
  /// files it left on disk (path relative to the package root → content).
  static Future<({GenerationReport report, Map<String, String> files})> run(
    String name,
    Map<String, String> files,
  ) async {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: $name\nenvironment:\n  sdk: ^3.13.0\n');
    Directory(dir.resolve('lib')).createSync();
    files.forEach(dir.write);
    await WorkspacePackageConfig.write(dir.path, name);
    final session = GenerationSession(PackageRoot.open(dir.path));
    try {
      final report = await session.run();
      return (report: report, files: _generated(dir, files.keys));
    } finally {
      await session.close();
    }
  }

  static Map<String, String> _generated(TempDir dir, Iterable<String> given) {
    final lib = Directory(dir.resolve('lib'));
    final found = {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        p.posix.joinAll(p.split(p.relative(file.path, from: dir.path))): file,
    };
    return {
      for (final MapEntry(:key, :value)
          in found.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        if (!given.contains(key)) key: value.readAsStringSync(),
    };
  }
}
