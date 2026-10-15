import 'package:code_builder/code_builder.dart';

/// Writes a `@override` getter that returns one expression.
abstract final class OverrideGetter {
  /// The getter [name] of type [type] that returns [value].
  static Method build(String name, Reference type, Expression value) => Method(
    (b) => b
      ..annotations.add(refer('override'))
      ..returns = type
      ..type = MethodType.getter
      ..name = name
      ..lambda = true
      ..body = value.code,
  );

  /// `List<element>`.
  static TypeReference listOf(Reference element) => TypeReference(
    (b) => b
      ..symbol = 'List'
      ..types.add(element),
  );
}
