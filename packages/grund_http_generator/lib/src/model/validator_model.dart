/// A constraint annotation (`@Range`, `@Length`, `@Pattern`, `@OneOf`) on a
/// route parameter.
sealed class ValidatorModel {
  /// Creates the validator.
  const ValidatorModel();

  /// The annotation as a user writes it, for messages.
  String get display;
}

/// `@Range(min:, max:)`.
final class RangeValidator extends ValidatorModel {
  /// Creates the validator.
  const RangeValidator({this.min, this.max});

  /// The smallest allowed value.
  final num? min;

  /// The largest allowed value.
  final num? max;

  @override
  String get display => '@Range';
}

/// `@Length(min:, max:)`.
final class LengthValidator extends ValidatorModel {
  /// Creates the validator.
  const LengthValidator({this.min, this.max});

  /// The shortest allowed length.
  final int? min;

  /// The longest allowed length.
  final int? max;

  @override
  String get display => '@Length';
}

/// `@Pattern(regex)`.
final class PatternValidator extends ValidatorModel {
  /// Creates the validator.
  const PatternValidator(this.regex);

  /// The regular expression source.
  final String regex;

  @override
  String get display => '@Pattern';
}

/// `@OneOf(values)`.
final class OneOfValidator extends ValidatorModel {
  /// Creates the validator.
  const OneOfValidator(this.values);

  /// The allowed values.
  final List<String> values;

  @override
  String get display => '@OneOf';
}
