import 'package:grund_generator/grund_generator.dart';

import 'dto_field.dart';

/// The shape of a class that is a request body or a handler result,
/// collected for documentation generators (OpenAPI in a later version).
final class DtoModel {
  /// Creates the model.
  const DtoModel({
    required this.type,
    required this.fields,
    required this.hasFromJson,
    this.documentation,
  });

  /// The class.
  final TypeModel type;

  /// Public instance fields, in declaration order.
  final List<DtoField> fields;

  /// Whether the class has a `fromJson` that takes a JSON object.
  final bool hasFromJson;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
