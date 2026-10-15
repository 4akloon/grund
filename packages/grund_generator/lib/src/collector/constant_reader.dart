import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/constant_value.dart';
import 'type_reader.dart';

/// Converts analyzer constants to [ConstantValue]s that the generator can
/// write back as code.
///
/// A constant that is a public named constant is kept as a reference
/// (`dbUrl`, `Status.active`); anything else is rebuilt from its value.
abstract final class ConstantReader {
  /// The model of [object].
  static ConstantValue read(DartObject? object) {
    if (object == null || !object.hasKnownValue) {
      return const UnsupportedConstant('its value is not known');
    }
    if (_reference(object.variable) case final reference?) return reference;
    if (object.isNull) return const NullConstant();
    final private =
        _privateClass(object.toTypeValue()) ?? _privateClass(object.type);
    if (private != null) return UnsupportedConstant('$private is private');
    return _primitive(object) ?? _collection(object) ?? _object(object);
  }

  static ReferenceConstant? _reference(VariableElement? variable) {
    final name = variable?.name;
    if (variable == null || name == null || !variable.isPublic) return null;
    final library = variable.library;
    if (library == null) return null;
    return switch (variable.enclosingElement) {
      LibraryElement() => ReferenceConstant(
        name: name,
        libraryUri: '${library.uri}',
      ),
      InterfaceElement(name: final owner?) when !owner.startsWith('_') =>
        ReferenceConstant(
          name: name,
          libraryUri: '${library.uri}',
          enclosingName: owner,
        ),
      _ => null,
    };
  }

  static ConstantValue? _primitive(DartObject object) {
    if (object.toBoolValue() case final value?) return BoolConstant(value);
    if (object.toIntValue() case final value?) return NumberConstant('$value');
    if (object.toDoubleValue() case final value?) {
      return value.isFinite
          ? NumberConstant('$value')
          : UnsupportedConstant('$value is not a finite number');
    }
    if (object.toStringValue() case final value?) return StringConstant(value);
    if (object.toTypeValue() case final type?) {
      return TypeConstant(TypeReader.read(type));
    }
    return null;
  }

  static ConstantValue? _collection(DartObject object) {
    final type = object.type;
    if (type is! InterfaceType) return null;
    final arguments = [for (final t in type.typeArguments) TypeReader.read(t)];
    if (object.toListValue() case final list?) {
      return ListConstant(arguments.single, [for (final e in list) read(e)]);
    }
    if (object.toSetValue() case final set?) {
      return SetConstant(arguments.single, [for (final e in set) read(e)]);
    }
    if (object.toMapValue() case final map?) {
      return MapConstant(arguments.first, arguments.last, [
        for (final MapEntry(:key, :value) in map.entries)
          (read(key), read(value)),
      ]);
    }
    return null;
  }

  static ConstantValue _object(DartObject object) {
    final invocation = object.constructorInvocation;
    final type = object.type;
    if (invocation == null || type is! InterfaceType) {
      return UnsupportedConstant(
        '${object.type?.getDisplayString() ?? 'it'} is not a constructor call, '
        'a literal or a public constant',
      );
    }
    final constructor = invocation.constructor;
    if (constructor.isPrivate) {
      return UnsupportedConstant(
        'the constructor ${constructor.displayName} is private',
      );
    }
    return ObjectConstant(
      type: TypeReader.read(type),
      constructorName: _constructorName(constructor),
      positional: [
        for (final value in invocation.positionalArguments) read(value),
      ],
      named: {
        for (final MapEntry(:key, :value) in invocation.namedArguments.entries)
          key: read(value),
      },
    );
  }

  /// The name of a private class in [type] or its type arguments.
  static String? _privateClass(DartType? type) {
    if (type is! InterfaceType) return null;
    final name = type.element.name ?? '';
    if (name.startsWith('_')) return name;
    return type.typeArguments.map(_privateClass).nonNulls.firstOrNull;
  }

  /// `''` for the unnamed constructor, whose name differs between analyzer
  /// versions (`''`, `new` or `null`).
  static String _constructorName(ConstructorElement constructor) =>
      switch (constructor.name) {
        null || '' || 'new' => '',
        final name => name,
      };
}
