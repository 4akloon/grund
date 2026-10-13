/// The outcome of reading one entry of an annotation list, such as
/// `@Module(providers: [...])`: a value, or a sentence on why it is invalid.
sealed class EntryRead<T> {
  const EntryRead();

  /// The values of the [ReadEntry] items of [reads], in order.
  static List<T> values<T>(Iterable<EntryRead<T>> reads) => [
    for (final read in reads)
      if (read case ReadEntry<T>(:final value)) value,
  ];

  /// The problems of the [InvalidEntry] items of [reads], in order.
  static List<String> problems(Iterable<EntryRead<Object>> reads) => [
    for (final read in reads)
      if (read case InvalidEntry<Object>(:final problem)) problem,
  ];
}

/// An entry read into [value].
final class ReadEntry<T> extends EntryRead<T> {
  /// Creates the outcome.
  const ReadEntry(this.value);

  /// The value read.
  final T value;
}

/// An entry the generator cannot use.
final class InvalidEntry<T> extends EntryRead<T> {
  /// Creates the outcome.
  const InvalidEntry(this.problem);

  /// Why the entry is invalid, as a sentence.
  final String problem;
}
