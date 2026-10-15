import '../generate/generation_report.dart';
import '../generate/write_outcome.dart';

/// Prints [GenerationReport]s: problems and their count to [err], the
/// outcome of a clean run to [out].
final class ReportPrinter {
  /// Creates the printer.
  const ReportPrinter(this.out, this.err);

  /// Where results go.
  final StringSink out;

  /// Where problems go.
  final StringSink err;

  /// Prints [report].
  void report(GenerationReport report) {
    if (report.hasProblems) {
      report.problemLines.forEach(err.writeln);
      final count = report.problemLines.length;
      err.writeln(
        '$count ${count == 1 ? 'problem' : 'problems'}; '
        '${report.output} was not changed.',
      );
      return;
    }
    final milliseconds = report.elapsed.inMilliseconds;
    out.writeln(switch (report.outcome) {
      WriteOutcome.written => 'Generated ${report.output} in $milliseconds ms.',
      WriteOutcome.unchanged =>
        '${report.output} is up to date ($milliseconds ms).',
      WriteOutcome.deleted =>
        'No annotations in lib/; deleted ${report.output}.',
      WriteOutcome.none => 'No annotations in lib/; nothing to generate.',
      WriteOutcome.kept => '${report.output} was not changed.',
    });
  }

  /// Prints that [directory] (relative to the package root) is watched.
  void watching(String directory) =>
      out.writeln('Watching $directory/ for changes; press Ctrl+C to stop.');
}
