/// The public library to import for each declaration of another package's
/// `src/` that one source library can see, by declaring library and name.
final class PublicImports {
  /// Creates the table from [uris], keyed as [key] writes.
  const PublicImports(this._uris);

  /// No declaration has a public library: every reference keeps its
  /// declaring library.
  static const none = PublicImports({});

  final Map<String, String> _uris;

  /// The key of the declaration [name] of the library at [declaringUri].
  static String key(String declaringUri, String name) => '$declaringUri#$name';

  /// The public library that exports the declaration [name] of the library
  /// at [declaringUri], or `null` when there is none.
  String? find(String declaringUri, String name) =>
      _uris[key(declaringUri, name)];
}
