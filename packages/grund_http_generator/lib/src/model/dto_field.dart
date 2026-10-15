import 'package:grund_generator/grund_generator.dart';

/// A field of a `DtoModel`.
final class DtoField {
  /// Creates the field.
  const DtoField({
    required this.name,
    required this.jsonName,
    required this.type,
    this.defaultValue,
    this.documentation,
  });

  /// The Dart field name.
  final String name;

  /// The JSON key: `@JsonKey(name:)` when present, otherwise [name].
  final String jsonName;

  /// The declared type; nullable fields have a nullable type.
  final TypeModel type;

  /// The default value of the matching constructor parameter, as source.
  final String? defaultValue;

  /// The `///` comment of the field, if any.
  final String? documentation;
}
