import 'dart:io';

import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';

/// The package a command works on: its root directory and the name from
/// its `pubspec.yaml`.
final class PackageRoot {
  const PackageRoot._(this.path, this.name);

  /// Reads the package at [directory].
  ///
  /// Throws a [CliFailure] with [CliExitCode.noInput] when there is no
  /// readable `pubspec.yaml` with a valid `name`, or no `lib/` directory.
  factory PackageRoot.open(String directory) {
    final root = p.normalize(p.absolute(directory));
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw CliFailure(
        CliExitCode.noInput,
        'No pubspec.yaml in $root; run the command in a package directory '
        'or pass --directory.',
      );
    }
    final name = _name(pubspec);
    if (!Directory(p.join(root, 'lib')).existsSync()) {
      throw CliFailure(CliExitCode.noInput, 'No lib/ directory in $root.');
    }
    return PackageRoot._(root, name);
  }

  /// A valid Dart package name.
  static final validName = LibraryWriter.validPackageName;

  /// Absolute, normalized path of the package root.
  final String path;

  /// The package name.
  final String name;

  /// Absolute path of `lib/`.
  String get libPath => p.join(path, 'lib');

  /// [file] relative to the package root with `/` separators, the way
  /// diagnostics print paths on every platform.
  String display(String file) =>
      p.posix.joinAll(p.split(p.relative(file, from: path)));

  static String _name(File pubspec) {
    final Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on YamlException catch (error) {
      throw CliFailure(
        CliExitCode.noInput,
        'Cannot read ${pubspec.path}: ${error.message}.',
      );
    } on FileSystemException catch (error) {
      throw CliFailure(
        CliExitCode.noInput,
        'Cannot read ${pubspec.path}: ${error.message}.',
      );
    }
    final name = document is YamlMap ? document['name'] : null;
    if (name is String && validName.hasMatch(name)) return name;
    throw CliFailure(
      CliExitCode.noInput,
      '${pubspec.path} has no valid package name '
      '(a "name:" in lowercase_with_underscores).',
    );
  }
}
