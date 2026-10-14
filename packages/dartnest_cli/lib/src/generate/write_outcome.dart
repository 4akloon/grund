/// What a generation did to the generated library on disk.
enum WriteOutcome {
  /// The library was written: it was missing or its content changed.
  written,

  /// The library already had the generated content; it was not touched.
  unchanged,

  /// The package has no annotations any more; the library was deleted.
  deleted,

  /// The package has no annotations and there is no library.
  none,

  /// The sources have problems; the library was left as it was.
  kept,
}
