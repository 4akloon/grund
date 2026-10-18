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
    this.outputDirectory = 'web/client',
    this.runner = const ProcessCompileRunner(),
  });

  /// The entry point of the browser code.
  static const String defaultEntry = 'lib/main.client.dart';

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
    final staging = Directory(
      p.join(package.path, '.dart_tool', 'grund_bundle'),
    );
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
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
  }

  void _swap(Directory staging, {required bool release}) {
    final output = Directory(p.join(package.path, outputDirectory))
      ..createSync(recursive: true);
    for (final file in _bundleFiles(output)) {
      file.deleteSync();
    }
    for (final file in _bundleFiles(staging)) {
      final name = p.basename(file.path);
      if (name.endsWith('.deps') || (release && name.endsWith('.map'))) {
        continue;
      }
      file.renameSync(p.join(output.path, name));
    }
  }

  Iterable<File> _bundleFiles(Directory directory) => directory
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).startsWith(outputName))
      .toList();
}
