import 'dart:io';

import 'package:path/path.dart' as p;

import '../package/package_root.dart';
import 'bundle_result.dart';
import 'compile_runner.dart';
import 'process_compile_runner.dart';

/// Compiles the browser entry of a package to JavaScript and swaps the
/// result into [outputDirectory].
///
/// The compiler writes into `.dart_tool/grund_bundle/` first (it leaves
/// `.deps` and, in release, `.map` files next to the bundle); only the
/// files of the new bundle move to the output, and only when the
/// compilation succeeded, so a failed build leaves the old bundle serving.
final class ClientBundler {
  /// Creates the bundler of [package] for [entry] (relative to the package),
  /// writing into [outputDirectory] (relative to the package, or absolute).
  ClientBundler(
    this.package, {
    this.entry = defaultEntry,
    this.outputDirectory = defaultOutputDirectory,
    this.runner = const ProcessCompileRunner(),
  });

  /// The entry point of the browser code.
  static const String defaultEntry = 'lib/main.client.dart';

  /// Where the bundle goes by default, relative to the package.
  static const String defaultOutputDirectory = 'web/client';

  /// The package to bundle.
  final PackageRoot package;

  /// The entry point, relative to the package.
  final String entry;

  /// The directory the bundle is moved to.
  final String outputDirectory;

  /// What compiles.
  final CompileRunner runner;

  /// The name of the bundle: the entry's file name with `.js`.
  String get outputName => '${p.basename(entry)}.js';

  /// Whether the entry point exists.
  bool get hasEntry => File(p.join(package.path, entry)).existsSync();

  /// Compiles the entry and replaces the old bundle files of the output
  /// directory with the new ones.
  ///
  /// With [release] the production flags are used and no source maps stay;
  /// without it the build is `-O1` with maps (for `dev`).
  Future<BundleResult> build({required bool release}) async {
    if (!hasEntry) return const BundleSkipped();
    final parent = Directory(p.join(package.path, '.dart_tool', 'grund_bundle'))
      ..createSync(recursive: true);
    // A directory per build: a `bundle` and a `dev` build never share one.
    final staging = parent.createTempSync('build_');
    try {
      final stopwatch = Stopwatch()..start();
      final outcome = await runner.compileJs(
        entry: entry,
        output: p.join(staging.path, outputName),
        release: release,
        workingDirectory: package.path,
      );
      stopwatch.stop();
      if (!outcome.succeeded) return BundleFailed(outcome.output);
      _swap(staging, release: release);
      return BundleBuilt(stopwatch.elapsed);
    } finally {
      staging.deleteSync(recursive: true);
    }
  }

  // New files first, so a failure half-way never leaves no bundle.
  void _swap(Directory staging, {required bool release}) {
    final output = Directory(p.join(package.path, outputDirectory))
      ..createSync(recursive: true);
    final moved = <String>{};
    for (final file in _bundleFiles(staging)) {
      final name = p.basename(file.path);
      if (name.endsWith('.deps') || (release && name.endsWith('.map'))) {
        continue;
      }
      _move(file, p.join(output.path, name));
      moved.add(name);
    }
    for (final file in _bundleFiles(output)) {
      if (!moved.contains(p.basename(file.path))) file.deleteSync();
    }
  }

  // The staging directory is under `.dart_tool/`, the output may be on
  // another filesystem, where a rename fails.
  void _move(File file, String target) {
    try {
      file.renameSync(target);
    } on FileSystemException {
      file
        ..copySync(target)
        ..deleteSync();
    }
  }

  Iterable<File> _bundleFiles(Directory directory) => directory
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).startsWith(outputName))
      .toList();
}
