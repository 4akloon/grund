import 'jaspr_error.dart';

/// A `PageSite` is declared in a way the framework cannot serve.
sealed class SiteDeclarationError extends JasprError {
  /// Creates the error.
  const SiteDeclarationError();
}

/// The path of a `PageSite` is not `''` or `/segment[/segment]`.
final class InvalidSitePathError extends SiteDeclarationError {
  /// Creates the error for the site [path]; [reason] says what is wrong.
  const InvalidSitePathError({required this.path, required this.reason});

  /// The invalid site path.
  final String path;

  /// What is wrong with [path].
  final String reason;

  @override
  String get message => 'Invalid site path "$path": $reason';
}
