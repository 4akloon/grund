import 'package:grund_generator/grund_generator.dart';

import 'param_source.dart';
import 'validator_model.dart';

/// A parameter of a route handler method.
final class ParamModel {
  /// Creates the model.
  const ParamModel({
    required this.name,
    required this.type,
    required this.source,
    required this.isNamed,
    required this.location,
    this.validators = const [],
    this.defaultValue,
  });

  /// The parameter name.
  final String name;

  /// The declared type.
  final TypeModel type;

  /// Where the value comes from.
  final ParamSource source;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;

  /// The validation annotations, in source order.
  final List<ValidatorModel> validators;

  /// The default value of an optional parameter; `null` when it has none.
  final ConstantValue? defaultValue;
}
