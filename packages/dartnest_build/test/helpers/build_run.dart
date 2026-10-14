import 'package:build/build.dart';
import 'package:build_test/build_test.dart';

/// One build of a package with build_test, in memory: the sources of every
/// package of the test's package config (so `package:dartnest_annotations`
/// and the workspace fixtures resolve without `pub get`), plus the given
/// files.
final class BuildRun {
  BuildRun._(this._output, this._result);

  /// Builds [package] with [builder]; [files] (path relative to the package
  /// root → content) are added to or replace its sources.
  ///
  /// A generated library the package already has is removed first, so
  /// [library] is always the builder's own output.
  static Future<BuildRun> run(
    Builder builder,
    String package, [
    Map<String, String> files = const {},
  ]) async {
    final readerWriter = TestReaderWriter(rootPackage: package);
    await readerWriter.testing.loadIsolateSources();
    final output = AssetId(package, 'lib/$package.dartnest.dart');
    if (readerWriter.testing.exists(output)) {
      readerWriter.testing.delete(output);
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
    return BuildRun._(output, result);
  }

  final AssetId _output;
  final TestBuilderResult _result;

  /// Whether the build succeeded.
  bool get succeeded => _result.succeeded;

  /// The errors the build logged, in order.
  List<String> get errors => [..._result.errors];

  /// The generated library, or `null` when the build did not write it.
  String? get library => _result.outputs.contains(_output)
      ? _result.readerWriter.testing.readString(_output)
      : null;
}
