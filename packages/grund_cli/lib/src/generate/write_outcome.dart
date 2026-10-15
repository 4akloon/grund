/// What a generation did to the generated files on disk.
enum WriteOutcome {
  /// At least one file was written or a stale one deleted.
  written,

  /// Every generated file already had the generated content.
  unchanged,

  /// The package has no annotations and no generated files.
  none,

  /// The sources have problems; the generated files were left as they were.
  kept,
}
