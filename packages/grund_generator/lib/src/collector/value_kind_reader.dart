import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/value_kind.dart';

/// Decides which `Params` reader fills a parameter of a given type.
abstract final class ValueKindReader {
  /// The kind of [type], whether nullable or not.
  static ValueKind read(DartType type) {
    if (type is! InterfaceType) return ValueKind.unsupported;
    if (type.element is EnumElement) return ValueKind.enumeration;
    if (type.isDartCoreString) return ValueKind.string;
    if (type.isDartCoreInt) return ValueKind.integer;
    if (type.isDartCoreDouble) return ValueKind.decimal;
    if (type.isDartCoreBool) return ValueKind.boolean;
    if (_isCore(type, 'DateTime')) return ValueKind.dateTime;
    if (_isCore(type, 'Uri')) return ValueKind.uri;
    return type.isDartCoreList && type.typeArguments.single.isDartCoreString
        ? ValueKind.stringList
        : ValueKind.unsupported;
  }

  static bool _isCore(InterfaceType type, String name) =>
      type.element.name == name && type.element.library.isDartCore;
}
