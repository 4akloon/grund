import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

import '../package/package_root.dart';
import 'default_generator.dart';
import 'generation_report.dart';
import 'output_writer.dart';
import 'package_analysis.dart';
import 'synced_files.dart';
import 'write_outcome.dart';

/// Generates one package again and again with the analyzer state kept in
/// memory: the first [run] resolves everything, later runs re-read only
/// the files they are told about. `gen`, `gen --watch` and `dev` drive it.
final class GenerationSession {
  /// Opens the session for [package], generating with [generator].
  GenerationSession(this.package, {this.generator = DefaultGenerator.instance})
    : _analysis = PackageAnalysis(package),
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
  /// The generated files are written only when the sources have no
  /// problems; otherwise none is touched.
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
      return _report(
        stopwatch,
        outcome: WriteOutcome.kept,
        syntax: syntaxProblems,
      );
    }
    final model = generator
        .collector(package.name, package.path)
        .collect(await _analysis.libraries(files));
    final result = generator.generate(model);
    if (!result.isSuccess) {
      return _report(
        stopwatch,
        outcome: WriteOutcome.kept,
        diagnostics: [...result.diagnostics]..sort(),
      );
    }
    final synced = _writer.sync(result.files);
    await _analysis.changed([
      for (final path in [...synced.written, ...synced.deleted])
        p.join(package.path, path),
    ]);
    return _report(stopwatch, outcome: synced.outcome, synced: synced);
  }

  /// Releases the analyzer's resources; the session cannot run again.
  Future<void> close() => _analysis.dispose();

  GenerationReport _report(
    Stopwatch stopwatch, {
    required WriteOutcome outcome,
    SyncedFiles? synced,
    List<SyntaxProblem> syntax = const [],
    List<Diagnostic> diagnostics = const [],
  }) => GenerationReport(
    outcome: outcome,
    elapsed: stopwatch.elapsed,
    synced: synced,
    syntaxProblems: syntax,
    diagnostics: diagnostics,
  );
}
