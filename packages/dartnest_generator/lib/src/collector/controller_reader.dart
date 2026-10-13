import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/controller_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'constructor_reader.dart';
import 'enhancers_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a `@Controller` class into a [ControllerModel].
final class ControllerReader {
  /// Creates the reader.
  ControllerReader(this.locations)
    : _constructors = ConstructorReader(locations),
      _routes = RouteReader(locations);

  /// Locations of declarations.
  final SourceLocations locations;

  final ConstructorReader _constructors;

  final RouteReader _routes;

  /// The controller declared by [element], whose `@Controller` is
  /// [annotation].
  ControllerModel read(ClassElement element, DartObject annotation) =>
      ControllerModel(
        type: TypeReader.read(element.thisType),
        path: Annotations.field(annotation, 'path')?.toStringValue() ?? '',
        constructor: _constructors.read(element),
        location: locations.of(element),
        enhancers: EnhancersReader.read(element),
        metadata: [
          for (final value in Annotations.routeMetadata(element))
            ConstantReader.read(value),
        ],
        routes: _routes.read(element),
        documentation: element.documentationComment,
      );
}
