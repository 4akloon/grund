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

/// A page is declared at a path the framework serves files from.
final class ReservedPagePathError extends PageDeclarationError {
  /// Creates the error for the page at [path]; [reason] says what it
  /// collides with.
  const ReservedPagePathError({required this.path, required this.reason});

  /// The full path of the page.
  final String path;

  /// What the path collides with.
  final String reason;

  @override
  String get message => 'The page path "$path" is reserved: $reason';
}

/// A page is declared at the path of another site or under it, where that
/// site's hooks would not apply.
final class MisplacedPagePathError extends PageDeclarationError {
  /// Creates the error for the page at [path] of [siteType], which lies in
  /// the territory of the site [owner].
  const MisplacedPagePathError({
    required this.path,
    required this.siteType,
    required this.owner,
  });

  /// The full path of the page.
  final String path;

  /// The site the page is declared under.
  final Type siteType;

  /// The site whose path the page lies on or under.
  final Type owner;

  @override
  String get message =>
      'The page "$path" of $siteType lies on the path of the site $owner, '
      'so it would bypass the hooks of $owner. Declare it with '
      'Pages.under<$owner> or move it to another path.';
}

/// A parameterised page in a site with a sitemap says neither where its
/// addresses are nor that it stays out.
final class UndecidedPageSitemapError extends PageDeclarationError {
  /// Creates the error for the page at [path].
  const UndecidedPageSitemapError(this.path);

  /// The full path of the page.
  final String path;

  @override
  String get message =>
      'The page $path has path parameters and its site has a '
      'baseUrl, but the page lists no addresses. Give it '
      'PageSitemap(entries: ...) or PageSitemap(included: false).';
}

/// A page without path parameters declares `entries`.
final class UnusedPageEntriesError extends PageDeclarationError {
  /// Creates the error for the page at [path].
  const UnusedPageEntriesError(this.path);

  /// The full path of the page.
  final String path;

  @override
  String get message =>
      'The page $path has PageSitemap.entries but no path parameter, so the '
      'entries would never be used. Remove the entries or add a ":param" to '
      'the path.';
}

/// A `PageAlternate` is declared in a way the framework cannot serve.
final class InvalidPageAlternateError extends PageDeclarationError {
  /// Creates the error for an alternate of [mediaType] of the page at
  /// [path]; [reason] says what is wrong.
  const InvalidPageAlternateError({
    required this.path,
    required this.mediaType,
    required this.reason,
  });

  /// The full path of the page.
  final String path;

  /// The media type of the alternate.
  final String mediaType;

  /// What is wrong with the alternate.
  final String reason;

  @override
  String get message =>
      'Invalid alternate "$mediaType" of the page $path: $reason';
}

/// A page lacks an alternate its site requires.
final class MissingPageAlternateError extends PageDeclarationError {
  /// Creates the error for the page at [path] without an alternate of
  /// [mediaType].
  const MissingPageAlternateError({
    required this.path,
    required this.mediaType,
  });

  /// The full path of the page.
  final String path;

  /// The media type the site requires.
  final String mediaType;

  @override
  String get message =>
      'The page $path has no alternate of $mediaType, but its site lists '
      '$mediaType in requiredAlternates. Add PageAlternate to the page.';
}
