import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/component_reference.dart';
import '../model/enhancers_model.dart';
import '../model/type_kind.dart';
import '../model/type_model.dart';
import 'annotations.dart';
import 'type_reader.dart';

/// Reads `@UseGuards`, `@UseInterceptors`, `@UsePipes` and `@UseFilters`
/// of a controller class or a handler method.
abstract final class EnhancersReader {
  /// The enhancers declared on [element]; several annotations of one kind
  /// add up in declaration order.
  static EnhancersModel read(Element element) => EnhancersModel(
    guards: _components(element, 'UseGuards', 'Guard'),
    interceptors: _components(element, 'UseInterceptors', 'Interceptor'),
    pipes: _components(element, 'UsePipes', 'Pipe'),
    filters: _components(element, 'UseFilters', 'ExceptionFilter'),
  );

  static List<ComponentReference> _components(
    Element element,
    String annotation,
    String interface,
  ) => [
    for (final use in Annotations.all(element, {annotation}))
      for (final type in _types(use)) _component(type, interface),
  ];

  static List<DartType?> _types(DartObject use) => [
    for (final entry
        in Annotations.field(use, 'types')?.toListValue() ??
            const <DartObject>[])
      entry.toTypeValue(),
  ];

  static ComponentReference _component(DartType? type, String interface) =>
      switch (type) {
        InterfaceType(:final element) => ComponentReference(
          TypeReader.read(type),
          isValid: TypeReader.hasSupertype(
            element,
            interface,
            'package:dartnest/',
          ),
        ),
        _ => ComponentReference(
          TypeModel(name: '$type', kind: TypeKind.unsupported),
          isValid: false,
        ),
      };
}
