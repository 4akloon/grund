import 'dart:io';

import 'package:path/path.dart' as p;

import '../package/package_root.dart';
import 'app_command.dart';

/// What `dev` runs: the entry point of [package] and the arguments of its
/// `main`.
final class DevTarget {
  /// Creates the target; [entry] is absolute.
  const DevTarget(
    this.package, {
    required this.entry,
    required this.arguments,
    this.environment = const {},
  });

  /// The package of the application.
  final PackageRoot package;

  /// The absolute path of the entry point.
  final String entry;

  /// The arguments of the application's `main`.
  final List<String> arguments;

  /// Variables added to the environment of the application.
  final Map<String, String> environment;

  /// The command line that runs the application in its package.
  AppCommand get command => AppCommand(
    entry,
    workingDirectory: package.path,
    arguments: arguments,
    environment: environment,
  );

  /// The Dart files the application is built from, as far as `dev` watches
  /// them: `lib/` and the directory of the entry point.
  List<String> sources() => [
    for (final directory in {package.libPath, p.dirname(entry)})
      ..._dartFiles(directory),
  ];

  static Iterable<String> _dartFiles(String directory) =>
      Directory(directory).existsSync()
      ? Directory(directory)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.endsWith('.dart'))
      : const <String>[];
}
