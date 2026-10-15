/// A constraint on a path, query, header or cookie parameter; a violation is
/// a 400 response with `code` and `pointer`.
sealed class ValidatorAnnotation {
  /// Creates the annotation.
  const ValidatorAnnotation();
}

/// The bounds of an `int` or `double` parameter, both inclusive.
final class Range extends ValidatorAnnotation {
  /// Creates the annotation; either bound may be left out.
  const Range({this.min, this.max});

  /// The smallest allowed value.
  final num? min;

  /// The largest allowed value.
  final num? max;
}

/// The length bounds of a `String` parameter, both inclusive.
final class Length extends ValidatorAnnotation {
  /// Creates the annotation; either bound may be left out.
  const Length({this.min, this.max});

  /// The shortest allowed length.
  final int? min;

  /// The longest allowed length.
  final int? max;
}

/// The regular expression a `String` parameter must match.
final class Pattern extends ValidatorAnnotation {
  /// Creates the annotation for [regex], a Dart `RegExp` source.
  const Pattern(this.regex);

  /// The regular expression source.
  final String regex;
}

/// The values a `String` parameter may have.
final class OneOf extends ValidatorAnnotation {
  /// Creates the annotation.
  const OneOf(this.values);

  /// The allowed values.
  final List<String> values;
}
