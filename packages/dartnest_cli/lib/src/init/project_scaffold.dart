import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import '../package/package_root.dart';
import 'project_template.dart';

/// Writes a new application from [ProjectTemplate] into an empty or new
/// directory; the directory name is the package name.
final class ProjectScaffold {
  /// Creates the scaffold of [directory].
  ProjectScaffold(String directory)
    : directory = p.normalize(p.absolute(directory));

  /// Absolute path of the new package.
  final String directory;

  /// The package name: the directory name.
  String get name => p.basename(directory);

  /// Writes the files and returns their paths relative to [directory].
  ///
  /// Throws a [CliFailure]: [CliExitCode.usage] for a directory name that
  /// is not a package name, [CliExitCode.cannotCreate] for a directory that
  /// is not empty or cannot be written.
  List<String> write() {
    if (!PackageRoot.validName.hasMatch(name)) {
      throw CliFailure(
        CliExitCode.usage,
        '"$name" is not a valid package name; name the directory in '
        'lowercase_with_underscores.',
      );
    }
    _checkEmpty();
    final files = ProjectTemplate.files(name);
    for (final MapEntry(key: path, value: content) in files.entries) {
      final file = File(p.joinAll([directory, ...path.split('/')]));
      try {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      } on FileSystemException catch (error) {
        throw CliFailure(
          CliExitCode.cannotCreate,
          'Cannot write ${file.path}: '
          '${error.osError?.message ?? error.message}.',
        );
      }
    }
    return files.keys.toList();
  }

  void _checkEmpty() {
    final type = FileSystemEntity.typeSync(directory);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory ||
        Directory(directory).listSync().isNotEmpty) {
      throw CliFailure(
        CliExitCode.cannotCreate,
        '$directory is not an empty directory; init writes a new package '
        'into an empty or new directory.',
      );
    }
  }
}
