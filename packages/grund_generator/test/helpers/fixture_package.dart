import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/model/generated_names.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:path/path.dart' as p;

/// A fixture package under `test/fixtures/<name>`, resolved with the
/// analyzer the way a driver would: every library of its `lib/` except the
/// generated `*.g.dart`.
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

  /// Opens a package at [root], for example a temporary one a test writes.
  factory FixturePackage.at(String name, String root) => FixturePackage._(
    name,
    root,
    AnalysisContextCollection(includedPaths: [root]),
  );

  /// The package name (also the directory name).
  final String name;

  /// Absolute path of the package root.
  final String root;

  final AnalysisContextCollection _collection;

  /// The resolved libraries of [paths] (relative to [root], for example
  /// `lib/users.dart`), or of every library in `lib/` when [paths] is
  /// `null`, in path order.
  Future<List<LibraryElement>> libraries([List<String>? paths]) async {
    final files = paths == null
        ? _libraryFiles()
        : [for (final path in paths) p.join(root, path)];
    return [for (final file in files) await _resolve(file)];
  }

  /// The [PackageModel] of [paths], as [libraries] reads them, with the
  /// annotations of the core constructs.
  Future<PackageModel> collect([List<String>? paths]) async =>
      const GrundGenerator.core()
          .collector(name, root)
          .collect(await libraries(paths));

  /// The source of [path] (relative to [root]).
  String read(String path) => File(p.join(root, path)).readAsStringSync();

  List<String> _libraryFiles() {
    final files = Directory(p.join(root, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.dart'))
        .where((path) => !path.endsWith(GeneratedNames.outputSuffix))
        .toList();
    return files..sort();
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
