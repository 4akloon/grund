import 'package:analyzer/dart/element/element.dart';

import '../construct/construct_annotations.dart';
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
  /// Creates the reader; the [annotations] a construct marks injectable
  /// make a class injectable.
  InjectableReader(this.locations, ConstructAnnotations annotations)
    : _source = Annotations(annotations.libraries),
      _injectable = annotations.injectable,
      _constructors = ConstructorReader(locations);

  /// Locations of classes and parameters.
  final SourceLocations locations;

  final Annotations _source;
  final Set<String> _injectable;
  final ConstructorReader _constructors;

  /// The model of [element].
  InjectableModel read(InterfaceElement element) {
    final injectable = _source.find(element, 'Injectable');
    final scope = LifetimeReader.read(injectable);
    return InjectableModel(
      type: TypeReader.read(element.thisType),
      name: _source.named(element),
      lifetime: scope.lifetime,
      scopeProblem: scope.problem,
      isAnnotated: _source.all(element, _injectable).isNotEmpty,
      constructor: _constructors.read(element),
      location: locations.of(element),
      documentation: element.documentationComment,
    );
  }
}
