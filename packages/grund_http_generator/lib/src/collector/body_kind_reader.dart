import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/body_kind.dart';

/// Decides how a `@Body()` parameter of a given type is read.
abstract final class BodyKindReader {
  /// The body kind of [type]: a class with `fromJson(Map<String, ...>)`, a
  /// list of them, a JSON object map, or raw bytes.
  static BodyKind read(DartType type) {
    if (type is! InterfaceType ||
        type.nullabilitySuffix != NullabilitySuffix.none) {
      return BodyKind.unsupported;
    }
    if (_isBytes(type)) return BodyKind.bytes;
    if (_isJsonObject(type)) return BodyKind.jsonObject;
    if (type.isDartCoreList) {
      final item = type.typeArguments.single;
      return item is InterfaceType &&
              item.nullabilitySuffix == NullabilitySuffix.none &&
              hasFromJson(item.element)
          ? BodyKind.list
          : BodyKind.unsupported;
    }
    return hasFromJson(type.element) ? BodyKind.object : BodyKind.unsupported;
  }

  /// Whether [element] has a `fromJson` constructor or static method whose
  /// only required parameter takes a `Map<String, ...>`.
  static bool hasFromJson(InterfaceElement element) {
    final ExecutableElement? fromJson =
        element.getNamedConstructor('fromJson') ??
        element.getMethod('fromJson');
    if (fromJson == null ||
        (fromJson is MethodElement && !fromJson.isStatic) ||
        element.typeParameters.isNotEmpty) {
      return false;
    }
    final required = [
      for (final parameter in fromJson.formalParameters)
        if (parameter.isRequired) parameter,
    ];
    return required.length == 1 &&
        required.single.isPositional &&
        _isJsonObject(required.single.type);
  }

  static bool _isBytes(InterfaceType type) =>
      (type.element.name == 'Uint8List' &&
          '${type.element.library.uri}' == 'dart:typed_data') ||
      (type.isDartCoreList && type.typeArguments.single.isDartCoreInt);

  static bool _isJsonObject(DartType type) =>
      type is InterfaceType &&
      type.isDartCoreMap &&
      type.typeArguments.first.isDartCoreString &&
      switch (type.typeArguments.last) {
        DynamicType() => true,
        final InterfaceType value =>
          value.isDartCoreObject &&
              value.nullabilitySuffix == NullabilitySuffix.question,
        _ => false,
      };
}
