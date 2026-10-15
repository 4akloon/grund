import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/route_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'hook_reader.dart';
import 'param_reader.dart';
import 'return_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads the route methods of a class.
final class RouteReader {
  /// Creates the reader.
  RouteReader(this.locations) : _parameters = ParamReader(locations);

  /// Locations of methods and parameters.
  final SourceLocations locations;

  final ParamReader _parameters;

  /// The names of the route annotations.
  static const annotations = {'Get', 'Post', 'Put', 'Patch', 'Delete'};

  /// The routes of [owner]: one per method with a route annotation, in
  /// declaration order.
  List<RouteModel> read(ClassElement owner) => [
    for (final method in owner.methods)
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
  }) {
    final hooks = HookReader.read(route);
    final verb = Annotations.field(route, 'method')?.toStringValue();
    final path = Annotations.field(route, 'path')?.toStringValue();
    return RouteModel(
      method: verb ?? '',
      path: path ?? '',
      handlerName: method.displayName,
      returnType: TypeReader.read(method.returnType),
      returnKind: ReturnReader.read(method.returnType),
      location: locations.of(method),
      status: Annotations.field(route, 'status')?.toIntValue(),
      parameters: [
        for (final parameter in method.formalParameters)
          _parameters.read(parameter),
      ],
      use: EntryRead.values(hooks),
      invalidEntries: EntryRead.problems(hooks),
      documentation: method.documentationComment,
      problem: verb == null || path == null
          ? 'The route annotation on ${method.displayName} needs a constant '
                'string path.'
          : _problem(method, isSingle: isSingle),
    );
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
