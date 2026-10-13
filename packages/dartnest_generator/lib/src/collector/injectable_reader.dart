import 'package:analyzer/dart/element/element.dart';

import '../model/injectable_model.dart';
import 'annotations.dart';
import 'constructor_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a class that dependency injection creates: a provider class, a
/// `Bind` implementation or a controller.
final class InjectableReader {
  /// Creates the reader.
  InjectableReader(this.locations)
    : _constructors = ConstructorReader(locations);

  /// Locations of classes and parameters.
  final SourceLocations locations;

  final ConstructorReader _constructors;

  /// The model of [element].
  InjectableModel read(InterfaceElement element) => InjectableModel(
    type: TypeReader.read(element.thisType),
    isAnnotated: Annotations.find(element, 'Injectable') != null,
    constructor: _constructors.read(element),
    location: locations.of(element),
    documentation: element.documentationComment,
  );
}
