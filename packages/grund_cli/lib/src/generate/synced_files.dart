import 'write_outcome.dart';

/// What writing the generated file set changed in a package, as paths
/// relative to the package root with `/` separators, sorted.
final class SyncedFiles {
  /// Creates the result of [written] and [deleted] paths out of [total]
  /// generated files.
  const SyncedFiles({
    required this.written,
    required this.deleted,
    required this.total,
  });

  /// The files that were created or whose content changed.
  final List<String> written;

  /// The stale generated files that were removed.
  final List<String> deleted;

  /// How many files the generator produced.
  final int total;

  /// What this amounts to: [WriteOutcome.written] when anything changed.
  WriteOutcome get outcome {
    if (written.isNotEmpty || deleted.isNotEmpty) return WriteOutcome.written;
    return total == 0 ? WriteOutcome.none : WriteOutcome.unchanged;
  }
}
