import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/type_kind.dart';
import '../model/type_model.dart';
import 'annotations.dart';

/// Converts analyzer types to [TypeModel]s.
abstract final class TypeReader {
  /// The model of [type].
  static TypeModel read(DartType type) => switch (type) {
    VoidType() => TypeModel.voidType,
    DynamicType() => const TypeModel(
      name: 'dynamic',
      kind: TypeKind.dynamicType,
    ),
    InterfaceType(:final element, :final typeArguments) => TypeModel(
      name: element.name ?? element.displayName,
      kind: element is EnumElement ? TypeKind.enumeration : TypeKind.interface,
      libraryUri: '${element.library.uri}',
      typeArguments: [for (final argument in typeArguments) read(argument)],
      isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
    ),
    _ => TypeModel(name: type.getDisplayString(), kind: TypeKind.unsupported),
  };

  /// Whether [type] is the class [name] of a `package:grund` library.
  static bool isGrund(DartType? type, String name) =>
      type is InterfaceType &&
      type.element.name == name &&
      _isIn(type.element.library, 'package:grund/');

  /// Whether [type] is the class [name] of a library under [uriPrefix].
  static bool isFrom(DartType? type, String name, String uriPrefix) =>
      type is InterfaceType &&
      type.element.name == name &&
      _isIn(type.element.library, uriPrefix);

  /// Whether [element] is, or extends, the base class `Module` of
  /// `package:grund`. The `Module` annotation lives in the same package and
  /// has the same name, so its library does not count.
  static bool extendsCoreModule(InterfaceElement element) =>
      [element.thisType, ...element.allSupertypes].any(
        (type) =>
            type.element.name == 'Module' &&
            _isIn(type.element.library, 'package:grund/') &&
            !_isIn(type.element.library, Annotations.coreLibrary),
      );

  static bool _isIn(LibraryElement library, String uriPrefix) =>
      '${library.uri}'.startsWith(uriPrefix);
}
