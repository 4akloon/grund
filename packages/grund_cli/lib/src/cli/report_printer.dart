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
        'no generated file was changed.',
      );
      return;
    }
    out.writeln(_outcome(report));
  }

  static String _outcome(GenerationReport report) {
    final milliseconds = report.elapsed.inMilliseconds;
    final written = report.synced?.written.length ?? 0;
    final deleted = report.synced?.deleted.length ?? 0;
    final total = report.synced?.total ?? 0;
    return switch (report.outcome) {
      WriteOutcome.written when total == 0 =>
        'No annotations in lib/; deleted ${_files(deleted, 'stale')}.',
      WriteOutcome.written =>
        'Generated ${_files(written)}'
            '${deleted == 0 ? '' : ', deleted ${_files(deleted, 'stale')}'}'
            ' in $milliseconds ms.',
      WriteOutcome.unchanged =>
        'Generated files are up to date (${_files(total)}, $milliseconds ms).',
      WriteOutcome.none => 'No annotations in lib/; nothing to generate.',
      WriteOutcome.kept => 'No generated file was changed.',
    };
  }

  static String _files(int count, [String? kind]) =>
      '$count ${kind == null ? '' : '$kind '}${count == 1 ? 'file' : 'files'}';

  /// Prints that [directory] (relative to the package root) is watched.
  void watching(String directory) =>
      out.writeln('Watching $directory/ for changes; press Ctrl+C to stop.');
}
