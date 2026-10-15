import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import 'annotations.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads what one parameter of a constructor or `@Provides` method resolves
/// to: its type and its `@Named` qualifier.
final class DependencyReader {
  /// Creates the reader.
  DependencyReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  /// The dependency [parameter] of [owner] (for example `UsersService` or
  /// `UsersModule.config`) declares.
  DependencyModel read(FormalParameterElement parameter, String owner) {
    final where = 'Parameter ${parameter.displayName} of $owner';
    if (parameter.isOptional) {
      return _invalid(
        parameter,
        '$where is optional; grund injects required positional and '
        'required named parameters only.',
      );
    }
    if (!_isInjectable(parameter.type)) {
      return _invalid(
        parameter,
        '$where has type ${parameter.type.getDisplayString()}; grund '
        'injects non-nullable class types, qualified with @Named.',
      );
    }
    return DependencyModel.injected(
      name: parameter.displayName,
      isNamed: parameter.isNamed,
      location: locations.of(parameter),
      key: BindingKey(
        TypeReader.read(parameter.type),
        Annotations.core.named(parameter),
      ),
    );
  }

  DependencyModel _invalid(FormalParameterElement parameter, String problem) =>
      DependencyModel.invalid(
        name: parameter.displayName,
        isNamed: parameter.isNamed,
        location: locations.of(parameter),
        problem: problem,
      );

  static bool _isInjectable(DartType type) =>
      type is InterfaceType &&
      type.nullabilitySuffix == NullabilitySuffix.none &&
      !type.isDartCoreObject;
}
