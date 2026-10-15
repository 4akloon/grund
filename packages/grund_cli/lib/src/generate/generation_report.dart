import 'package:grund_generator/grund_generator.dart';

import 'synced_files.dart';
import 'write_outcome.dart';

/// The result of one generation: the problems found, what happened to the
/// generated files and how long it took.
final class GenerationReport {
  /// Creates the report.
  const GenerationReport({
    required this.outcome,
    required this.elapsed,
    this.synced,
    this.syntaxProblems = const [],
    this.diagnostics = const [],
  });

  /// What happened to the generated files.
  final WriteOutcome outcome;

  /// How long the generation took.
  final Duration elapsed;

  /// The files written and deleted, and how many were generated; `null`
  /// when the sources have problems and nothing was written.
  final SyncedFiles? synced;

  /// Syntax errors in `lib/`, sorted; the generator did not run.
  final List<SyntaxProblem> syntaxProblems;

  /// The generator's diagnostics, sorted.
  final List<Diagnostic> diagnostics;

  /// The generated files written or deleted by this run, relative to the
  /// package root.
  List<String> get changedFiles => [...?synced?.written, ...?synced?.deleted];

  /// Whether the sources have problems ([outcome] is then
  /// [WriteOutcome.kept]).
  bool get hasProblems => syntaxProblems.isNotEmpty || diagnostics.isNotEmpty;

  /// Every problem as printed, one per line: syntax errors, then
  /// diagnostics.
  List<String> get problemLines => [
    for (final problem in syntaxProblems) '$problem',
    for (final diagnostic in diagnostics) '$diagnostic',
  ];
}
