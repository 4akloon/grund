/// What a reassemble changed in what the runners serve, as sorted strings a
/// runner chooses (the HTTP server uses `'GET /users/:id'`).
final class ReassembleReport {
  /// Creates the report.
  const ReassembleReport({this.added = const [], this.removed = const []});

  /// Compares the lists [before] and [after] a reassemble.
  factory ReassembleReport.between(List<String> before, List<String> after) {
    final old = before.toSet();
    final current = after.toSet();
    return ReassembleReport(
      added: List.unmodifiable(
        [
          for (final entry in after)
            if (!old.contains(entry)) entry,
        ]..sort(),
      ),
      removed: List.unmodifiable(
        [
          for (final entry in before)
            if (!current.contains(entry)) entry,
        ]..sort(),
      ),
    );
  }

  /// A report of a reassemble that changed nothing.
  static const none = ReassembleReport();

  /// What is served now and was not before, sorted.
  final List<String> added;

  /// What was served before and is not now, sorted.
  final List<String> removed;

  /// How many entries were added or removed.
  int get changed => added.length + removed.length;

  /// This report and [other] as one, sorted.
  ReassembleReport merge(ReassembleReport other) => ReassembleReport(
    added: List.unmodifiable([...added, ...other.added]..sort()),
    removed: List.unmodifiable([...removed, ...other.removed]..sort()),
  );

  /// The report as JSON, for the `ext.grund.reassemble` service extension.
  Map<String, Object> toJson() => {'added': added, 'removed': removed};
}
