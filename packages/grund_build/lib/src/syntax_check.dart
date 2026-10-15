import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

/// Finds the syntax errors of a library and its part files, as the CLI
/// reports them.
final class SyntaxCheck {
  /// Creates the check of the files of [package], read through [resolver].
  const SyntaxCheck(this.package, this.resolver);

  /// The package whose files are checked; build_runner's analyzer sees its
  /// files under `/<package>/`, and locations are relative to that root.
  final String package;

  /// Where the sources come from.
  final Resolver resolver;

  /// The syntax errors of the library at [library] and its part files,
  /// sorted by location; empty when it parses.
  ///
  /// Resolving the library, not parsing its unit alone, is what reports
  /// the errors of its part files. The resolver throws only on error
  /// severity, while the CLI prints every parse diagnostic; the parser emits
  /// only errors, so they agree.
  Future<List<SyntaxProblem>> of(AssetId library) async {
    try {
      await resolver.libraryFor(library);
      return const [];
    } on SyntaxErrorInAssetException catch (error) {
      return [
        for (final file in error.filesWithErrors)
          for (final diagnostic in file.diagnostics)
            SyntaxProblem(
              _location(file.path, file.lineInfo, diagnostic.offset),
              diagnostic.message,
            ),
      ]..sort();
    }
  }

  SourceLocation _location(String path, LineInfo lines, int offset) {
    final position = lines.getLocation(offset);
    return SourceLocation(
      p.posix.relative(path, from: '/$package'),
      position.lineNumber,
      position.columnNumber,
    );
  }
}
