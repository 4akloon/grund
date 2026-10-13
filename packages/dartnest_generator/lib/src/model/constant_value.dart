import 'type_model.dart';

/// A compile-time constant read from an annotation, in a form the
/// generator can write back as Dart code.
sealed class ConstantValue {
  /// Creates the value.
  const ConstantValue();

  /// The first part of this value that cannot be written as code, or
  /// `null` when all of it can.
  UnsupportedConstant? get unsupported => switch (this) {
    final UnsupportedConstant self => self,
    ListConstant(:final elements) ||
    SetConstant(:final elements) => _firstUnsupported(elements),
    MapConstant(:final entries) => _firstUnsupported([
      for (final (key, value) in entries) ...[key, value],
    ]),
    ObjectConstant(:final positional, :final named) => _firstUnsupported([
      ...positional,
      ...named.values,
    ]),
    _ => null,
  };

  static UnsupportedConstant? _firstUnsupported(List<ConstantValue> values) {
    for (final value in values) {
      if (value.unsupported case final found?) return found;
    }
    return null;
  }
}

/// `null`.
final class NullConstant extends ConstantValue {
  /// Creates the value.
  const NullConstant();
}

/// `true` or `false`.
final class BoolConstant extends ConstantValue {
  /// Creates the value.
  const BoolConstant(this.value);

  /// The value.
  final bool value;
}

/// An `int` or `double`, kept as its Dart literal.
final class NumberConstant extends ConstantValue {
  /// Creates the value from its literal, for example `42` or `0.5`.
  const NumberConstant(this.literal);

  /// The Dart literal.
  final String literal;
}

/// A `String`.
final class StringConstant extends ConstantValue {
  /// Creates the value.
  const StringConstant(this.value);

  /// The string, unescaped.
  final String value;
}

/// A list literal.
final class ListConstant extends ConstantValue {
  /// Creates the value.
  const ListConstant(this.elementType, this.elements);

  /// The element type argument.
  final TypeModel elementType;

  /// The elements.
  final List<ConstantValue> elements;
}

/// A set literal.
final class SetConstant extends ConstantValue {
  /// Creates the value.
  const SetConstant(this.elementType, this.elements);

  /// The element type argument.
  final TypeModel elementType;

  /// The elements.
  final List<ConstantValue> elements;
}

/// A map literal.
final class MapConstant extends ConstantValue {
  /// Creates the value.
  const MapConstant(this.keyType, this.valueType, this.entries);

  /// The key type argument.
  final TypeModel keyType;

  /// The value type argument.
  final TypeModel valueType;

  /// The entries, in order.
  final List<(ConstantValue, ConstantValue)> entries;
}

/// A type literal such as `UsersService`.
final class TypeConstant extends ConstantValue {
  /// Creates the value.
  const TypeConstant(this.type);

  /// The type.
  final TypeModel type;
}

/// A named constant: a top-level `const`, a static `const` field or an
/// enum value.
final class ReferenceConstant extends ConstantValue {
  /// Creates the reference.
  const ReferenceConstant({
    required this.name,
    required this.libraryUri,
    this.enclosingName,
  });

  /// The variable name.
  final String name;

  /// URI of the declaring library.
  final String libraryUri;

  /// The class or enum that declares a static field; `null` for top-level.
  final String? enclosingName;
}

/// A `const` constructor call.
final class ObjectConstant extends ConstantValue {
  /// Creates the value.
  const ObjectConstant({
    required this.type,
    required this.constructorName,
    this.positional = const [],
    this.named = const {},
  });

  /// The created type, with its type arguments.
  final TypeModel type;

  /// The constructor name; empty for the unnamed constructor.
  final String constructorName;

  /// Positional arguments.
  final List<ConstantValue> positional;

  /// Named arguments, in source order.
  final Map<String, ConstantValue> named;
}

/// A constant the generator cannot write as code.
final class UnsupportedConstant extends ConstantValue {
  /// Creates the value with the reason.
  const UnsupportedConstant(this.reason);

  /// Why the constant cannot be written, as a sentence fragment.
  final String reason;
}
