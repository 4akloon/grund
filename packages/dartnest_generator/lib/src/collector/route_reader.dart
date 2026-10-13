import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/route_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'enhancers_reader.dart';
import 'handler_parameter_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads the handler methods of a `@Controller` class.
final class RouteReader {
  /// Creates the reader.
  RouteReader(this.locations) : _parameters = HandlerParameterReader(locations);

  /// Locations of methods and parameters.
  final SourceLocations locations;

  final HandlerParameterReader _parameters;

  /// The names of the route annotations.
  static const annotations = {'Get', 'Post', 'Put', 'Patch', 'Delete'};

  /// The routes of [controller]: one per method with a route annotation,
  /// in declaration order.
  List<RouteModel> read(ClassElement controller) => [
    for (final method in controller.methods)
      if (Annotations.all(method, annotations) case [
        final first,
        ...final rest,
      ])
        _route(method, first, isSingle: rest.isEmpty),
  ];

  RouteModel _route(
    MethodElement method,
    DartObject route, {
    required bool isSingle,
  }) => RouteModel(
    method: _string(method, route, 'method'),
    path: _string(method, route, 'path'),
    handlerName: method.displayName,
    returnType: TypeReader.read(method.returnType),
    location: locations.of(method),
    parameters: [
      for (final parameter in method.formalParameters)
        _parameters.read(parameter),
    ],
    enhancers: EnhancersReader.read(method),
    metadata: [
      for (final value in Annotations.routeMetadata(method))
        ConstantReader.read(value),
    ],
    documentation: method.documentationComment,
    problem: _problem(method, isSingle: isSingle),
  );

  /// The string field [field] of the route annotation [route] on [method].
  static String _string(MethodElement method, DartObject route, String field) {
    final value = Annotations.field(route, field)?.toStringValue();
    if (value == null) {
      throw StateError(
        'The route annotation on ${method.displayName} has no constant '
        'string "$field".',
      );
    }
    return value;
  }

  static String? _problem(MethodElement method, {required bool isSingle}) {
    final name =
        '${method.enclosingElement?.displayName}.${method.displayName}';
    if (!isSingle) return 'Handler $name has more than one route annotation.';
    if (method.isStatic) return 'Handler $name is static.';
    if (method.isPrivate) return 'Handler $name is private.';
    if (method.typeParameters.isNotEmpty) return 'Handler $name is generic.';
    return null;
  }
}
