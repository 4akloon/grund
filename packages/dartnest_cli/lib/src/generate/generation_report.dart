import 'package:dartnest_generator/dartnest_generator.dart';

import 'write_outcome.dart';

/// The result of one generation: the problems found, what happened to the
/// generated library and how long it took.
final class GenerationReport {
  /// Creates the report.
  const GenerationReport({
    required this.output,
    required this.outcome,
    required this.elapsed,
    this.syntaxProblems = const [],
    this.diagnostics = const [],
  });

  /// The generated library, relative to the package root
  /// (`lib/shop.dartnest.dart`).
  final String output;

  /// What happened to [output].
  final WriteOutcome outcome;

  /// How long the generation took.
  final Duration elapsed;

  /// Syntax errors in `lib/`, sorted; the generator did not run.
  final List<SyntaxProblem> syntaxProblems;

  /// The generator's diagnostics, sorted.
  final List<Diagnostic> diagnostics;

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
