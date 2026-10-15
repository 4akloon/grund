import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

/// Generates the files of the package at [root] (a directory with a
/// `pubspec.yaml` named [name], after `dart pub get`) and returns them by
/// path; throws a [StateError] listing the diagnostics on problems.
///
/// This is what `grund_cli gen` does, without the writing, the watching
/// and the incremental analysis.
Future<Map<String, String>> generatePackage(String name, String root) async {
  final lib = p.join(p.normalize(p.absolute(root)), 'lib');
  final collection = AnalysisContextCollection(includedPaths: [lib]);
  try {
    final libraries = <LibraryElement>[
      for (final file in _sourceFiles(lib)) await _resolve(collection, file),
    ];
    const generator = GrundGenerator.core();
    final model = generator.collector(name, p.dirname(lib)).collect(libraries);
    final result = generator.generate(model);
    if (!result.isSuccess) throw StateError(result.diagnostics.join('\n'));
    return result.files;
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
      .where((path) => !path.endsWith(GeneratedNames.outputSuffix))
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

/// Prints the files generated for `<name> <directory>`, for example
/// `dart run example/grund_generator_example.dart cases_app
/// test/fixtures/cases_app`.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: grund_generator_example.dart <name> <directory>');
    exitCode = 64;
    return;
  }
  final files = await generatePackage(arguments[0], arguments[1]);
  for (final MapEntry(key: path, value: content) in files.entries) {
    stdout.write('// $path\n$content');
  }
}
