import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

import '../package/package_root.dart';
import 'generation_report.dart';
import 'output_writer.dart';
import 'package_analysis.dart';
import 'write_outcome.dart';

/// Generates one package again and again with the analyzer state kept in
/// memory: the first [run] resolves everything, later runs re-read only
/// the files they are told about. `gen`, `gen --watch` and `dev` drive it.
final class GenerationSession {
  /// Opens the session for [package], generating with [generator].
  GenerationSession(
    this.package, {
    this.generator = const GrundGenerator.core(),
  }) : _analysis = PackageAnalysis(package),
       _writer = OutputWriter(package);

  /// The generated package.
  final PackageRoot package;

  /// The constructs that run.
  final GrundGenerator generator;

  final PackageAnalysis _analysis;
  final OutputWriter _writer;

  /// Generates the package; [changed] lists the absolute paths added,
  /// modified or removed since the previous run of this session.
  ///
  /// Throws a `CliFailure` when an output file cannot be written.
  Future<GenerationReport> run({Iterable<String> changed = const []}) async {
    final stopwatch = Stopwatch()..start();
    await _analysis.changed([
      for (final path in changed)
        if (p.isWithin(package.libPath, path)) path,
    ]);
    final files = _analysis.sourceFiles();
    final syntaxProblems = _analysis.syntaxProblems(files);
    if (syntaxProblems.isNotEmpty) {
      return _report(stopwatch, WriteOutcome.kept, syntax: syntaxProblems);
    }
    final libraries = await _analysis.libraries(files);
    final model = PackageCollector(
      package.name,
      package.path,
    ).collect(libraries);
    if (model.isEmpty) {
      return _report(stopwatch, await _written(_writer.deleteLibrary()));
    }
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) {
      return _report(
        stopwatch,
        WriteOutcome.kept,
        diagnostics: [...result.diagnostics]..sort(),
      );
    }
    for (final file in result.files) {
      _writer.writeFile(file);
    }
    return _report(stopwatch, await _written(_writer.writeLibrary(library)));
  }

  /// Releases the analyzer's resources; the session cannot run again.
  Future<void> close() => _analysis.dispose();

  Future<WriteOutcome> _written(WriteOutcome outcome) async {
    if (outcome == WriteOutcome.written || outcome == WriteOutcome.deleted) {
      await _analysis.changed([package.outputPath]);
    }
    return outcome;
  }

  GenerationReport _report(
    Stopwatch stopwatch,
    WriteOutcome outcome, {
    List<SyntaxProblem> syntax = const [],
    List<Diagnostic> diagnostics = const [],
  }) => GenerationReport(
    output: package.display(package.outputPath),
    outcome: outcome,
    elapsed: stopwatch.elapsed,
    syntaxProblems: syntax,
    diagnostics: diagnostics,
  );
}
