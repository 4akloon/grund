import 'package:build/build.dart';
import 'package:grund_generator/grund_generator.dart';

import 'grund_build_options.dart';
import 'package_sources.dart';

/// Writes `lib/<package>.grund.dart` of package [packageName] from the
/// annotations of its `lib/`, as `grund_cli gen` does: the same files
/// are read, the same constructs run and the same bytes are written.
///
/// An aggregating builder on `lib/$lib$`: one build step reads every
/// source of `lib/`. Problems are logged as errors, one per line, in the
/// CLI's `path:line:column: error: message [code]` form, and fail the
/// build; nothing is written then.
final class GrundBuilder implements Builder {
  /// Creates the builder of package [packageName], generating with
  /// [generator].
  GrundBuilder(
    this.packageName, {
    this.generator = const GrundGenerator.core(),
  });

  /// The package whose library this builder writes.
  final String packageName;

  /// The constructs that run.
  final GrundGenerator generator;

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['$packageName.grund.dart'],
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
      AssetId(package, 'lib/$package.grund.dart'),
      library,
    );
  }

  static void _fail(Iterable<Object> problems) {
    for (final problem in problems) {
      log.severe('$problem');
    }
  }

  String _misnamed(String package) =>
      'grund_build cannot build $package: its build.yaml names the '
      'package "$packageName". Name the package in its build.yaml:\n\n'
      '${GrundBuildOptions.buildYaml(package)}';

  static String _unwritable(FileUnit file) =>
      'grund_build cannot write ${file.path}: a construct generated it, '
      'and a build_runner builder writes only lib/<package>.grund.dart. '
      'Generate this package with grund_cli gen.';
}
