/// What a reassemble added to and removed from what the application's
/// runners serve, as the strings the runners chose (the HTTP server uses
/// `GET /tasks/:id`).
final class ServedChanges {
  /// Creates the changes.
  const ServedChanges({this.added = const [], this.removed = const []});

  /// Reads the answer of the `ext.grund.reassemble` extension
  /// (`{"applications": n, "added": [...], "removed": [...]}`). An answer
  /// without the two lists is read as no changes.
  factory ServedChanges.fromResponse(Map<String, Object?>? json) =>
      switch (json) {
        {
          'added': final List<Object?> added,
          'removed': final List<Object?> removed,
        } =>
          ServedChanges(
            added: [for (final entry in added) '$entry'],
            removed: [for (final entry in removed) '$entry'],
          ),
        _ => const ServedChanges(),
      };

  /// What is served now and was not before.
  final List<String> added;

  /// What was served before and is not now.
  final List<String> removed;

  /// How many entries were added or removed.
  int get count => added.length + removed.length;
}
