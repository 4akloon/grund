import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import '../package/package_root.dart';
import 'project_template.dart';
import 'reserved_names.dart';

/// Writes a new application from [ProjectTemplate] into an empty or new
/// directory; the directory name is the package name.
final class ProjectScaffold {
  /// Creates the scaffold of [directory]; [writeFile] replaces the file
  /// write (a seam for failure tests).
  ProjectScaffold(String directory, {void Function(File, String)? writeFile})
    : directory = p.normalize(p.absolute(directory)),
      _writeFile = writeFile ?? _write;

  final void Function(File, String) _writeFile;

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
    final reason = ReservedNames.reasonFor(name);
    if (reason != null) {
      throw CliFailure(
        CliExitCode.usage,
        '"$name" is not a valid package name: it is $reason.',
      );
    }
    final existed = _checkEmpty();
    final files = ProjectTemplate.files(name);
    for (final MapEntry(key: path, value: content) in files.entries) {
      final file = File(p.joinAll([directory, ...path.split('/')]));
      try {
        file.parent.createSync(recursive: true);
        _writeFile(file, content);
      } on FileSystemException catch (error) {
        _cleanUp(existed: existed);
        throw CliFailure(
          CliExitCode.cannotCreate,
          'Cannot write ${file.path}: '
          '${error.osError?.message ?? error.message}.',
        );
      }
    }
    return files.keys.toList();
  }

  static void _write(File file, String content) =>
      file.writeAsStringSync(content);

  /// Removes what this run created: the directory itself when it did not
  /// exist, otherwise its content (it was empty).
  void _cleanUp({required bool existed}) {
    try {
      final root = Directory(directory);
      if (!existed) {
        root.deleteSync(recursive: true);
        return;
      }
      for (final entity in root.listSync()) {
        entity.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // Best effort: the write failure is the error worth reporting.
    }
  }

  /// Throws unless [directory] is new or empty; returns whether it existed.
  bool _checkEmpty() {
    final type = FileSystemEntity.typeSync(directory);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory ||
        Directory(directory).listSync().isNotEmpty) {
      throw CliFailure(
        CliExitCode.cannotCreate,
        '$directory is not an empty directory; init writes a new package '
        'into an empty or new directory.',
      );
    }
    return true;
  }
}
