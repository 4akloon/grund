import 'package:analyzer/dart/element/element.dart';

import '../model/injectable_model.dart';
import 'annotations.dart';
import 'constructor_reader.dart';
import 'lifetime_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a class that dependency injection creates: a provider class, a
/// `Bind` implementation or a class carrying an annotation a construct
/// marks injectable.
final class InjectableReader {
  /// Creates the reader; [annotations] are the class annotations that make
  /// a class injectable.
  InjectableReader(this.locations, this.annotations)
    : _constructors = ConstructorReader(locations);

  /// Locations of classes and parameters.
  final SourceLocations locations;

  /// The class annotations that make a class injectable.
  final Set<String> annotations;

  final ConstructorReader _constructors;

  /// The model of [element].
  InjectableModel read(InterfaceElement element) {
    final injectable = Annotations.find(element, 'Injectable');
    final scope = LifetimeReader.read(injectable);
    return InjectableModel(
      type: TypeReader.read(element.thisType),
      name: Annotations.named(element),
      lifetime: scope.lifetime,
      scopeProblem: scope.problem,
      isAnnotated: Annotations.all(element, annotations).isNotEmpty,
      constructor: _constructors.read(element),
      location: locations.of(element),
      documentation: element.documentationComment,
    );
  }
}
