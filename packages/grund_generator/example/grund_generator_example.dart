import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

/// Generates the grund library of the package at [root] (a directory
/// with a `pubspec.yaml` named [name], after `dart pub get`) and returns
/// its source; throws a [StateError] listing the diagnostics on problems.
///
/// This is what `grund_cli gen` does, without the writing, the watching
/// and the incremental analysis.
Future<String> generatePackage(String name, String root) async {
  final lib = p.join(p.normalize(p.absolute(root)), 'lib');
  final collection = AnalysisContextCollection(includedPaths: [lib]);
  try {
    final libraries = <LibraryElement>[
      for (final file in _sourceFiles(lib)) await _resolve(collection, file),
    ];
    final model = PackageCollector(name, p.dirname(lib)).collect(libraries);
    final result = const GrundGenerator.core().generate(model);
    return switch (result.library) {
      final library? => library,
      null => throw StateError(result.diagnostics.join('\n')),
    };
  } finally {
    await collection.dispose();
  }
}

List<String> _sourceFiles(String lib) {
  final files = Directory(lib)
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => path.endsWith('.dart'))
      .where((path) => !path.endsWith('.grund.dart'))
      .toList();
  return files..sort();
}

Future<LibraryElement> _resolve(
  AnalysisContextCollection collection,
  String file,
) async {
  final session = collection.contextFor(file).currentSession;
  return switch (await session.getResolvedLibrary(file)) {
    final ResolvedLibraryResult result => result.element,
    final other => throw StateError('Cannot resolve $file: $other'),
  };
}

/// Prints the library generated for `<name> <directory>`, for example
/// `dart run example/grund_generator_example.dart users_app
/// test/fixtures/users_app`.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: grund_generator_example.dart <name> <directory>');
    exitCode = 64;
    return;
  }
  stdout.write(await generatePackage(arguments[0], arguments[1]));
}
