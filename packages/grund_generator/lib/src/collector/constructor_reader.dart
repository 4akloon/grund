import 'package:analyzer/dart/element/element.dart';

import '../model/constructor_model.dart';
import 'dependency_reader.dart';
import 'source_locations.dart';

/// Reads how dependency injection creates a class: its unnamed constructor
/// and what each parameter resolves to.
final class ConstructorReader {
  /// Creates the reader.
  ConstructorReader(SourceLocations locations)
    : _dependencies = DependencyReader(locations);

  final DependencyReader _dependencies;

  /// The constructor model of [element].
  ConstructorModel read(InterfaceElement element) {
    final name = element.displayName;
    final constructor = element.unnamedConstructor;
    if (element is! ClassElement) {
      return ConstructorModel.invalid('$name is not a class.');
    }
    if (element.isPrivate) return ConstructorModel.invalid('$name is private.');
    if (element.typeParameters.isNotEmpty) {
      return ConstructorModel.invalid(
        '$name is generic; provide a subclass with fixed type arguments.',
      );
    }
    if (constructor == null) {
      return ConstructorModel.invalid(
        '$name has no unnamed constructor; grund creates it with '
        '$name(...).',
      );
    }
    if (element.isAbstract && !constructor.isFactory) {
      return ConstructorModel.invalid('$name is abstract.');
    }
    return ConstructorModel([
      for (final parameter in constructor.formalParameters)
        _dependencies.read(parameter, name),
    ]);
  }
}
