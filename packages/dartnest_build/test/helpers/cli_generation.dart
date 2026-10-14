import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';

import 'temp_dir.dart';
import 'workspace_package_config.dart';

/// What `dartnest_cli gen` does with a package: its report and the
/// generated library it left on disk.
typedef CliResult = ({GenerationReport report, String? library});

/// Runs the CLI's generation once over a fresh package outside the
/// workspace, resolved against this checkout without `pub get`.
abstract final class CliGeneration {
  /// Generates package [name] made of [files] (path relative to the
  /// package root → content).
  static Future<CliResult> run(String name, Map<String, String> files) async {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: $name\nenvironment:\n  sdk: ^3.8.0\n');
    Directory(dir.resolve('lib')).createSync();
    files.forEach(dir.write);
    await WorkspacePackageConfig.write(dir.path, name);
    final session = GenerationSession(PackageRoot.open(dir.path));
    try {
      final report = await session.run();
      final output = 'lib/$name.dartnest.dart';
      return (
        report: report,
        library: dir.exists(output) ? dir.read(output) : null,
      );
    } finally {
      await session.close();
    }
  }
}
