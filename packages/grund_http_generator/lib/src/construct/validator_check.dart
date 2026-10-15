import 'package:grund_generator/grund_generator.dart';

import '../diagnostic/http_diagnostic_codes.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/validator_model.dart';
import '../model/value_kind.dart';

/// Checks `@Range`, `@Length`, `@Pattern` and `@OneOf` against the
/// parameter they are on.
abstract final class ValidatorCheck {
  /// The problems of the validators of [param].
  static Iterable<Diagnostic> check(ParamModel param) sync* {
    for (final validator in param.validators) {
      final problem = _problem(param, validator);
      if (problem == null) continue;
      yield Diagnostic(
        HttpDiagnosticCodes.invalidValidator,
        param.location,
        '${validator.display} on parameter ${param.name}: $problem',
      );
    }
  }

  static String? _problem(ParamModel param, ValidatorModel validator) {
    final kind = switch (param.source) {
      ValueSource(:final kind) => kind,
      _ => null,
    };
    return switch (validator) {
      RangeValidator(:final min, :final max) =>
        _onlyOn(kind, const {
              ValueKind.integer,
              ValueKind.decimal,
            }, 'int or double') ??
            _order(min, max),
      LengthValidator(:final min, :final max) =>
        _onlyOn(kind, const {ValueKind.string}, 'String') ?? _order(min, max),
      PatternValidator(:final regex) =>
        _onlyOn(kind, const {ValueKind.string}, 'String') ?? _pattern(regex),
      OneOfValidator(:final values) =>
        _onlyOn(kind, const {ValueKind.string}, 'String') ??
            (values.isEmpty ? 'the list of values is empty.' : null),
    };
  }

  static String? _onlyOn(
    ValueKind? kind,
    Set<ValueKind> allowed,
    String what,
  ) => kind != null && allowed.contains(kind)
      ? null
      : 'it can only be used on a $what value parameter.';

  static String? _order(num? min, num? max) =>
      min != null && max != null && min > max
      ? 'min ($min) is greater than max ($max).'
      : null;

  static String? _pattern(String regex) {
    try {
      RegExp(regex);
      return null;
    } on FormatException catch (error) {
      return 'the pattern is not a valid regular expression: ${error.message}';
    }
  }
}
