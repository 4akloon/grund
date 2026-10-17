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
