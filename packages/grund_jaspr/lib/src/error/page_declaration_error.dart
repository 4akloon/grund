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

/// A page skips a hook type its site does not allow to skip.
final class ForbiddenPageSkipError extends PageDeclarationError {
  /// Creates the error for the page at [path] skipping [type].
  const ForbiddenPageSkipError({required this.path, required this.type});

  /// The full path of the page.
  final String path;

  /// The hook type the page tries to skip.
  final Type type;

  @override
  String get message =>
      'The page $path skips $type, but its site does not list $type in '
      'skippableHooks. Add it to the site\'s skippableHooks or remove it '
      'from the page\'s PageHooks.skip.';
}

/// A page skips a hook type that is not among the hooks of its site.
final class UnknownPageSkipError extends PageDeclarationError {
  /// Creates the error for the page at [path] skipping [type]; [siteHooks]
  /// are the hook types of the site.
  const UnknownPageSkipError({
    required this.path,
    required this.type,
    required this.siteHooks,
  });

  /// The full path of the page.
  final String path;

  /// The hook type the page tries to skip.
  final Type type;

  /// The hook types of the site, in order.
  final List<Type> siteHooks;

  @override
  String get message =>
      'The page $path skips $type, but the hooks of its site are '
      '${siteHooks.isEmpty ? 'none' : siteHooks.join(', ')}. A page skips a '
      'hook by its exact type; a base type or a subtype does not match.';
}

/// A page skips a hook type that occurs more than once in its site.
final class AmbiguousPageSkipError extends PageDeclarationError {
  /// Creates the error for the page at [path] skipping [type].
  const AmbiguousPageSkipError({required this.path, required this.type});

  /// The full path of the page.
  final String path;

  /// The hook type the page tries to skip.
  final Type type;

  @override
  String get message =>
      'The page $path skips $type, but the hooks of its site contain $type '
      'more than once, so it is unclear which one to skip.';
}
