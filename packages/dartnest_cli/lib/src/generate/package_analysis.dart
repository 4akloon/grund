import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import '../package/package_root.dart';
import 'syntax_problem.dart';

/// The analyzer's view of a package's `lib/`, kept in memory between
/// generations so that a later run re-reads only the files it is told
/// about.
final class PackageAnalysis {
  /// Opens the analysis of [package]'s `lib/`.
  PackageAnalysis(this.package)
    : _collection = AnalysisContextCollection(includedPaths: [package.libPath]);

  /// The analyzed package.
  final PackageRoot package;

  final AnalysisContextCollection _collection;

  /// Absolute paths of the Dart files of `lib/` except generated
  /// `*.dartnest.dart` files, sorted.
  ///
  /// Throws a [CliFailure] with [CliExitCode.noInput] when `lib/` or one of
  /// its directories cannot be listed (deleted meanwhile, unreadable).
  List<String> sourceFiles() {
    try {
      final files = [
        for (final entity in Directory(
          package.libPath,
        ).listSync(recursive: true, followLinks: false))
          if (entity is File && _isSource(entity.path)) entity.path,
      ];
      return files..sort();
    } on FileSystemException catch (error) {
      throw CliFailure(
        CliExitCode.noInput,
        'Cannot list ${package.display(error.path ?? package.libPath)}: '
        '${error.osError?.message ?? error.message}.',
      );
    }
  }

  /// Tells the analyzer that [paths] were added, modified or removed, and
  /// waits until it has read them.
  Future<void> changed(Iterable<String> paths) async {
    for (final path in paths) {
      _collection.contextFor(path).changeFile(path);
    }
    for (final context in _collection.contexts) {
      await context.applyPendingFileChanges();
    }
  }

  /// The syntax errors of [files], sorted by location.
  List<SyntaxProblem> syntaxProblems(List<String> files) {
    final problems = [for (final file in files) ..._syntaxProblemsOf(file)];
    return problems..sort();
  }

  /// The resolved libraries among [files]; part files are skipped.
  ///
  /// Throws a [CliFailure] with [CliExitCode.noInput] for a file the
  /// analyzer cannot read.
  Future<List<LibraryElement>> libraries(List<String> files) async {
    final libraries = <LibraryElement>[];
    for (final file in files) {
      final session = _collection.contextFor(file).currentSession;
      switch (await session.getResolvedLibrary(file)) {
        case ResolvedLibraryResult(:final element):
          libraries.add(element);
        case NotLibraryButPartResult():
          continue;
        case final other:
          throw CliFailure(
            CliExitCode.noInput,
            'Cannot analyze ${package.display(file)}: ${other.runtimeType}.',
          );
      }
    }
    return libraries;
  }

  /// Releases the analyzer's resources.
  Future<void> dispose() => _collection.dispose();

  Iterable<SyntaxProblem> _syntaxProblemsOf(String file) {
    final session = _collection.contextFor(file).currentSession;
    final result = session.getParsedUnit(file);
    if (result is! ParsedUnitResult) return const [];
    return [
      for (final diagnostic in result.diagnostics)
        SyntaxProblem(
          _location(file, result, diagnostic.offset),
          diagnostic.message,
        ),
    ];
  }

  SourceLocation _location(String file, ParsedUnitResult unit, int offset) {
    final position = unit.lineInfo.getLocation(offset);
    return SourceLocation(
      package.display(file),
      position.lineNumber,
      position.columnNumber,
    );
  }

  static bool _isSource(String path) =>
      path.endsWith('.dart') && !path.endsWith('.dartnest.dart');
}
