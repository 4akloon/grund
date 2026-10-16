// Fails when a package's real `dependencies` do not resolve against pub.dev.
//
// Usage: dart .github/scripts/check_published_dependencies.dart <package>
//
// The package's pubspec is copied to a temporary directory without
// `resolution: workspace`, `dev_dependencies` and `dependency_overrides`, and
// `dart pub get` runs there, outside the workspace: this is what pub.dev
// sees. A constraint on a workspace package whose version is not on pub.dev
// yet (its tag has not been pushed or published) fails here, before the
// publish step. Plain text processing, so no package is needed on the runner.
import 'dart:io';

const _strippedKeys = {
  'resolution',
  'dev_dependencies',
  'dependency_overrides',
};

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: check_published_dependencies.dart <package>');
    exit(64);
  }
  final package = arguments.single;
  final pubspec = File('packages/$package/pubspec.yaml').readAsStringSync();
  final temp = Directory.systemTemp.createTempSync('published_deps_');
  try {
    File('${temp.path}/pubspec.yaml').writeAsStringSync(_strip(pubspec));
    final result = await Process.run('dart', [
      'pub',
      'get',
    ], workingDirectory: temp.path);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stdout.writeln(
        '::error::The dependencies of $package do not resolve on pub.dev. '
        'Workspace dependencies: ${_workspaceDependencies(pubspec)}. '
        'Push the tag of the dependency whose version is not live yet, wait '
        'until it is on pub.dev, then re-run this job.',
      );
      exit(1);
    }
    stdout.writeln('The dependencies of $package resolve on pub.dev.');
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// [pubspec] without the top-level keys of [_strippedKeys] and their blocks.
String _strip(String pubspec) {
  final kept = <String>[];
  var skipping = false;
  for (final line in pubspec.split('\n')) {
    final isTopLevelKey = RegExp(r'^[A-Za-z_]').hasMatch(line);
    if (isTopLevelKey) {
      skipping = _strippedKeys.contains(line.split(':').first.trim());
    }
    if (!skipping) kept.add(line);
  }
  return kept.join('\n');
}

/// The `dependencies` of [pubspec] that are packages of this workspace.
String _workspaceDependencies(String pubspec) {
  final found = <String>[];
  var inDependencies = false;
  for (final line in pubspec.split('\n')) {
    if (RegExp(r'^[A-Za-z_]').hasMatch(line)) {
      inDependencies = line.startsWith('dependencies:');
      continue;
    }
    final match = RegExp(r'^  (\w+): (.+)$').firstMatch(line);
    if (inDependencies &&
        match != null &&
        Directory('packages/${match.group(1)}').existsSync()) {
      found.add('${match.group(1)} ${match.group(2)}');
    }
  }
  return found.join(', ');
}
