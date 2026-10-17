import 'jaspr_error.dart';

/// The pages of a running application cannot be read.
sealed class PageRuntimeError extends JasprError {
  /// Creates the error.
  const PageRuntimeError();
}

/// The `PageCatalog` was used before the application prepared its runners,
/// so no page snapshot exists yet.
final class PageCatalogNotReadyError extends PageRuntimeError {
  /// Creates the error.
  const PageCatalogNotReadyError();

  @override
  String get message =>
      'The PageCatalog has no pages yet: the application has not been '
      'started. Read the catalog after App.start (or TestApp.start), not '
      'while the providers are created.';
}

/// The `entries` of a parameterised page returned an entry whose
/// parameters are not the ones in the page path.
final class PageEntriesMismatchError extends PageRuntimeError {
  /// Creates the error for the page at [path]: the path has the parameters
  /// [expected], the entry has [actual].
  const PageEntriesMismatchError({
    required this.path,
    required this.expected,
    required this.actual,
  });

  /// The full path of the page.
  final String path;

  /// The parameter names of the path.
  final List<String> expected;

  /// The parameter names of the entry.
  final List<String> actual;

  @override
  String get message =>
      'The sitemap entries of $path have the parameters '
      '${actual.join(', ')}, but the path has ${expected.join(', ')}. Return '
      'entries whose params keys are exactly the names of the path.';
}
