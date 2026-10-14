import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'dartnest_build_options.dart';
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
    if (package != packageName) return _fail([_misnamed(package)]);
    final sources = await PackageSources.find(buildStep);
    final syntaxProblems = await sources.syntaxProblems();
    if (syntaxProblems.isNotEmpty) return _fail(syntaxProblems);
    // Diagnostic paths are relative to this root: build_runner's analyzer
    // sees the files of package p under /p/.
    final model = PackageCollector(
      package,
      '/$package',
    ).collect(await sources.libraries());
    if (model.isEmpty) return;
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) return _fail([...result.diagnostics]..sort());
    if (result.files.isNotEmpty) {
      return _fail([for (final file in result.files) _unwritable(file)]);
    }
    await buildStep.writeAsString(
      AssetId(package, 'lib/$package.dartnest.dart'),
      library,
    );
  }

  static void _fail(Iterable<Object> problems) {
    for (final problem in problems) {
      log.severe('$problem');
    }
  }

  String _misnamed(String package) =>
      'dartnest_build cannot build $package: its build.yaml names the '
      'package "$packageName". Name the package in its build.yaml:\n\n'
      '${DartnestBuildOptions.buildYaml(package)}';

  static String _unwritable(FileUnit file) =>
      'dartnest_build cannot write ${file.path}: a construct generated it, '
      'and a build_runner builder writes only lib/<package>.dartnest.dart. '
      'Generate this package with dartnest_cli gen.';
}
