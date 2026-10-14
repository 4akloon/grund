import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'package_sources.dart';

/// Writes `lib/<package>.dartnest.dart` of package [packageName] from the
/// annotations of its `lib/`, as `dartnest_cli gen` does: the same files
/// are read, the same constructs run and the same bytes are written.
///
/// An aggregating builder on `lib/$lib$`: one build step reads every
/// source of `lib/`. Problems are logged as errors, one per line, in the
/// CLI's `path:line:column: error: message [code]` form, and fail the
/// build; nothing is written then.
final class DartnestBuilder implements Builder {
  /// Creates the builder of package [packageName], generating with
  /// [generator].
  DartnestBuilder(
    this.packageName, {
    this.generator = const DartnestGenerator.core(),
  });

  /// The package whose library this builder writes.
  final String packageName;

  /// The constructs that run.
  final DartnestGenerator generator;

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['$packageName.dartnest.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final sources = await PackageSources.find(buildStep);
    // Diagnostic paths are relative to this root: build_runner's analyzer
    // sees the files of package p under /p/.
    final model = PackageCollector(
      package,
      '/$package',
    ).collect(await sources.libraries());
    if (model.isEmpty) return;
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) {
      result.diagnostics.map((diagnostic) => '$diagnostic').forEach(log.severe);
      return;
    }
    await buildStep.writeAsString(
      AssetId(package, 'lib/$package.dartnest.dart'),
      library,
    );
  }
}
