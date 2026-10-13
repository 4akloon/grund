import 'package:code_builder/code_builder.dart';

import '../model/constant_value.dart';
import 'dart_string.dart';
import 'type_emitter.dart';

/// Writes [ConstantValue]s as expressions.
abstract final class ConstantEmitter {
  /// [value] as an expression; a collection or constructor call is `const`
  /// at the top and plain inside, as the lints expect. An
  /// [UnsupportedConstant] must have been reported before generation.
  static Expression expression(ConstantValue value) =>
      _write(value, isConst: true);

  /// [values] as one `const` list literal.
  static Expression list(List<ConstantValue> values) =>
      literalConstList([for (final value in values) _write(value)]);

  static Expression _write(ConstantValue value, {bool isConst = false}) =>
      switch (value) {
        NullConstant() => literalNull,
        BoolConstant(:final value) => literalBool(value),
        NumberConstant(:final literal) => CodeExpression(Code(literal)),
        StringConstant(:final value) => CodeExpression(
          Code(DartString.literal(value)),
        ),
        TypeConstant(:final type) => TypeEmitter.reference(type),
        ReferenceConstant(
          :final name,
          :final libraryUri,
          :final enclosingName,
        ) =>
          enclosingName == null
              ? refer(name, libraryUri)
              : refer(enclosingName, libraryUri).property(name),
        ListConstant(:final elementType, :final elements) =>
          (isConst ? literalConstList : literalList)([
            for (final element in elements) _write(element),
          ], TypeEmitter.reference(elementType)),
        SetConstant(:final elementType, :final elements) =>
          (isConst ? literalConstSet : literalSet)({
            for (final element in elements) _write(element),
          }, TypeEmitter.reference(elementType)),
        MapConstant(:final keyType, :final valueType, :final entries) =>
          (isConst ? literalConstMap : literalMap)(
            {for (final (key, value) in entries) _write(key): _write(value)},
            TypeEmitter.reference(keyType),
            TypeEmitter.reference(valueType),
          ),
        ObjectConstant() => _object(value, isConst: isConst),
        UnsupportedConstant(:final reason) => throw StateError(
          'An unsupported constant reached generation: $reason.',
        ),
      };

  static Expression _object(ObjectConstant value, {required bool isConst}) {
    final type = TypeEmitter.reference(value.type);
    final positional = [for (final v in value.positional) _write(v)];
    final named = {
      for (final MapEntry(:key, :value) in value.named.entries)
        key: _write(value),
    };
    final name = value.constructorName;
    if (isConst) {
      return name.isEmpty
          ? type.constInstance(positional, named)
          : type.constInstanceNamed(name, positional, named);
    }
    return name.isEmpty
        ? type.newInstance(positional, named)
        : type.newInstanceNamed(name, positional, named);
  }
}
