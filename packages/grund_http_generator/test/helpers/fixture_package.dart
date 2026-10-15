import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:path/path.dart' as p;

/// A fixture package under `test/fixtures/<name>`, resolved with the
/// analyzer the way a driver would: every library of its `lib/` except the
/// generated `*.grund.dart`.
///
/// One instance holds one analysis context; open it once per test file
/// (`setUpAll`), because resolving the SDK takes a few seconds.
final class FixturePackage {
  FixturePackage._(this.name, this.root, this._collection);

  /// Opens `test/fixtures/<name>`; tests run from the package directory.
  factory FixturePackage.open(String name) {
    final root = p.normalize(p.absolute('test', 'fixtures', name));
    return FixturePackage._(
      name,
      root,
      AnalysisContextCollection(includedPaths: [root]),
    );
  }

  /// The constructs of a driver that generates modules and apis.
  static const constructs = [ModuleConstruct(), ApiConstruct()];

  /// The package name (also the directory name).
  final String name;

  /// Absolute path of the package root.
  final String root;

  final AnalysisContextCollection _collection;

  /// The [PackageModel] of [paths] (relative to [root], for example
  /// `lib/apis/tasks.dart`), collected with [constructs].
  Future<PackageModel> collect(List<String> paths) async {
    final libraries = [
      for (final path in paths) await _resolve(p.join(root, path)),
    ];
    return const GrundGenerator(
      constructs,
    ).collector(name, root).collect(libraries);
  }

  Future<LibraryElement> _resolve(String file) async {
    final session = _collection.contextFor(file).currentSession;
    final result = await session.getResolvedLibrary(file);
    if (result is! ResolvedLibraryResult) {
      throw StateError('Cannot resolve $file: $result');
    }
    return result.element;
  }
}
