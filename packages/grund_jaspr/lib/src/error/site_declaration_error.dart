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

/// Two sites of different declarations claim the same path.
final class DuplicateSitePathError extends SiteDeclarationError {
  /// Creates the error for the site [path].
  const DuplicateSitePathError(this.path);

  /// The path both sites claim; `''` is the root site.
  final String path;

  @override
  String get message =>
      'Two sites have the path "$path". Give one of them another path.';
}

/// A site lies under the path of another site.
final class NestedSitePathError extends SiteDeclarationError {
  /// Creates the error: the site at [inner] lies under the site at [outer].
  const NestedSitePathError({required this.outer, required this.inner});

  /// The path of the enclosing site.
  final String outer;

  /// The path of the nested site.
  final String inner;

  @override
  String get message =>
      'The site at "$inner" lies under the site at "$outer", so it would '
      'bypass the hooks of "$outer". Move it to a path outside "$outer".';
}

/// The same site type is declared in more than one module.
final class DuplicateSiteError extends SiteDeclarationError {
  /// Creates the error for [siteType].
  const DuplicateSiteError(this.siteType);

  /// The site type declared twice.
  final Type siteType;

  @override
  String get message =>
      'The site $siteType is declared more than once. Call Pages.site<'
      '$siteType> in one module only and export Key<$siteType>().';
}

/// The factory of `Pages.site<S>` returned an object that is not exactly an
/// `S`.
final class MismatchedSiteTypeError extends SiteDeclarationError {
  /// Creates the error: the site was declared as [expected] but is an
  /// [actual].
  const MismatchedSiteTypeError({required this.expected, required this.actual});

  /// The declared site type.
  final Type expected;

  /// The runtime type of the object the factory returned.
  final Type actual;

  @override
  String get message =>
      'Pages.site<$expected> created a $actual. A site is declared with its '
      'exact type: declare Pages.site<$actual> instead, or return a '
      '$expected.';
}

/// A site has no page at its root, `/`.
final class MissingSiteIndexError extends SiteDeclarationError {
  /// Creates the error for [siteType].
  const MissingSiteIndexError(this.siteType);

  /// The site without a root page.
  final Type siteType;

  @override
  String get message =>
      'The site $siteType has no page "/". Add Page(\'/\', ...) in a '
      'Pages.under<$siteType> declaration.';
}
