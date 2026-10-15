import 'package:build/build.dart';
import 'package:build_test/build_test.dart';

/// One build of a package with build_test, in memory: the sources of every
/// package of the test's package config (so `package:grund` and the
/// workspace fixtures resolve without `pub get`), plus the given files.
final class BuildRun {
  BuildRun._(this._package, this._result);

  /// Builds [package] with [builder]; [files] (path relative to the package
  /// root → content) are the package's sources, every one of them a build
  /// input.
  ///
  /// The generated files the package already has in the workspace are
  /// removed first, so [outputs] holds only what the builder wrote.
  static Future<BuildRun> run(
    Builder builder,
    String package,
    Map<String, String> files,
  ) async {
    final readerWriter = TestReaderWriter(rootPackage: package);
    await readerWriter.testing.loadIsolateSources();
    for (final asset in readerWriter.testing.assets.toList()) {
      if (asset.package == package && _isOutputName(asset.path)) {
        readerWriter.testing.delete(asset);
      }
    }
    final result = await testBuilder(
      builder,
      {
        for (final MapEntry(:key, :value) in files.entries)
          '$package|$key': value,
      },
      rootPackage: package,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    return BuildRun._(package, result);
  }

  static bool _isOutputName(String path) =>
      path.endsWith('_module.g.dart') || path.endsWith('_api.g.dart');

  final String _package;
  final TestBuilderResult _result;

  /// Whether the build succeeded.
  bool get succeeded => _result.succeeded;

  /// The errors the build logged, in order.
  List<String> get errors => [..._result.errors];

  /// What the builder wrote: path relative to the package root → content,
  /// in path order.
  Map<String, String> get outputs => {
    for (final id
        in _result.outputs.where((id) => id.package == _package).toList()
          ..sort())
      id.path: _result.readerWriter.testing.readString(id),
  };
}
