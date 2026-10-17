import 'jaspr_error.dart';

/// A `Page` is declared in a way the framework cannot serve.
sealed class PageDeclarationError extends JasprError {
  /// Creates the error.
  const PageDeclarationError();
}

/// The path of a `Page` is not a valid page path.
final class InvalidPagePathError extends PageDeclarationError {
  /// Creates the error for the page [path]; [reason] says what is wrong.
  const InvalidPagePathError({required this.path, required this.reason});

  /// The invalid page path.
  final String path;

  /// What is wrong with [path].
  final String reason;

  @override
  String get message => 'Invalid page path "$path": $reason';
}
