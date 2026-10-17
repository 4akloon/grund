/// One `/`-separated segment of a `RoutePattern`.
sealed class PatternSegment {
  /// Creates a segment.
  const PatternSegment();
}

/// A literal segment, matched exactly (case-sensitive).
final class StaticSegment extends PatternSegment {
  /// Creates a literal segment.
  const StaticSegment(this.value);

  /// The literal text.
  final String value;

  @override
  String toString() => value;
}

/// A `:name` segment that matches any single segment, or, with a [suffix]
/// such as `.md` (`:slug.md`), any segment that ends with it and has a
/// non-empty rest.
final class ParamSegment extends PatternSegment {
  /// Creates a parameter segment.
  const ParamSegment(this.name, {this.suffix = ''});

  /// Parameter name, without the colon.
  final String name;

  /// Literal text the matched segment must end with (`.tar.gz`), or empty.
  final String suffix;

  @override
  String toString() => ':$name$suffix';
}

/// A trailing `*` that matches one or more remaining segments; the match is
/// available as parameter `*`.
final class WildcardSegment extends PatternSegment {
  /// Creates the wildcard.
  const WildcardSegment();

  /// Name under which the matched rest of the path is captured.
  static const parameterName = '*';

  @override
  String toString() => '*';
}
