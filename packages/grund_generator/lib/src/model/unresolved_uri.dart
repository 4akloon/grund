import '../diagnostic/source_location.dart';

/// An `import`, `export` or `part` of a source library whose URI does not
/// resolve to a file.
final class UnresolvedUri {
  /// Creates the model.
  const UnresolvedUri({
    required this.uri,
    required this.directive,
    required this.location,
  });

  /// The URI as written in the directive.
  final String uri;

  /// The directive keyword: `import`, `export` or `part`.
  final String directive;

  /// Where the directive starts.
  final SourceLocation location;
}
