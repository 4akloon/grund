import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:glob/glob.dart';

/// The Dart sources of a package's `lib/` as one build step sees them:
/// every `*.dart` asset except generated `*.dartnest.dart` files, sorted by
/// path, the files `dartnest_cli gen` reads.
final class PackageSources {
  PackageSources._(this._step, this.assets);

  /// Finds the sources of the package [step] builds.
  static Future<PackageSources> find(BuildStep step) async {
    final assets = await step
        .findAssets(_dartFiles)
        .where((asset) => !asset.path.endsWith('.dartnest.dart'))
        .toList();
    return PackageSources._(step, assets..sort());
  }

  static final _dartFiles = Glob('lib/**.dart');

  final BuildStep _step;

  /// The sources, sorted by path.
  final List<AssetId> assets;

  /// The syntax errors of [assets], part files included, sorted by
  /// location: what the parser reports, as the CLI reports it.
  Future<List<SyntaxProblem>> syntaxProblems() async {
    final problems = [
      for (final asset in assets) ...await _syntaxProblemsOf(asset),
    ];
    return problems..sort();
  }

  /// The resolved libraries among [assets]; part files are skipped.
  Future<List<LibraryElement>> libraries() async {
    final resolver = _step.resolver;
    return [
      for (final asset in assets)
        if (await resolver.isLibrary(asset)) await resolver.libraryFor(asset),
    ];
  }

  Future<List<SyntaxProblem>> _syntaxProblemsOf(AssetId asset) async {
    // compilationUnitFor throws only on Severity.error, while the CLI prints
    // every parse diagnostic; the parser emits only errors, so they agree.
    try {
      await _step.resolver.compilationUnitFor(asset);
      return const [];
    } on SyntaxErrorInAssetException catch (error) {
      return [
        for (final file in error.filesWithErrors)
          for (final diagnostic in file.diagnostics)
            SyntaxProblem(
              _location(asset, file.lineInfo, diagnostic.offset),
              diagnostic.message,
            ),
      ];
    }
  }

  static SourceLocation _location(AssetId asset, LineInfo lines, int offset) {
    final position = lines.getLocation(offset);
    return SourceLocation(
      asset.path,
      position.lineNumber,
      position.columnNumber,
    );
  }
}
