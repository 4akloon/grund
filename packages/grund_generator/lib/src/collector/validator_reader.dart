import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/validator_model.dart';
import 'annotations.dart';

/// Reads `@Range`, `@Length`, `@Pattern` and `@OneOf` of a parameter.
abstract final class ValidatorReader {
  static const _names = {'Range', 'Length', 'Pattern', 'OneOf'};

  /// The validators of [parameter], in source order.
  static List<ValidatorModel> read(Element parameter) => [
    for (final annotation in Annotations.all(parameter, _names))
      _validator(annotation),
  ];

  static ValidatorModel _validator(DartObject annotation) =>
      switch (annotation.type?.element?.name) {
        'Range' => RangeValidator(
          min: _number(annotation, 'min'),
          max: _number(annotation, 'max'),
        ),
        'Length' => LengthValidator(
          min: Annotations.field(annotation, 'min')?.toIntValue(),
          max: Annotations.field(annotation, 'max')?.toIntValue(),
        ),
        'Pattern' => PatternValidator(
          Annotations.field(annotation, 'regex')?.toStringValue() ?? '',
        ),
        _ => OneOfValidator([
          for (final value
              in Annotations.field(annotation, 'values')?.toListValue() ??
                  const <DartObject>[])
            if (value.toStringValue() case final text?) text,
        ]),
      };

  static num? _number(DartObject annotation, String field) {
    final value = Annotations.field(annotation, field);
    return value?.toIntValue() ?? value?.toDoubleValue();
  }
}
