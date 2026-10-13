import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/constructor_model.dart';
import '../model/dependency_model.dart';
import '../model/provider_key.dart';
import 'annotations.dart';
import 'source_locations.dart';
import 'token_reader.dart';
import 'type_reader.dart';

/// Reads how dependency injection creates a class: its unnamed constructor
/// and what each parameter resolves to.
final class ConstructorReader {
  /// Creates the reader.
  ConstructorReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

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
        '$name has no unnamed constructor; dartnest creates it with '
        '$name(...).',
      );
    }
    if (element.isAbstract && !constructor.isFactory) {
      return ConstructorModel.invalid('$name is abstract.');
    }
    return ConstructorModel([
      for (final parameter in constructor.formalParameters)
        _dependency(element, parameter),
    ]);
  }

  DependencyModel _dependency(
    ClassElement owner,
    FormalParameterElement parameter,
  ) {
    final where = _where(owner, parameter);
    if (parameter.isOptional) {
      return _invalid(
        parameter,
        '$where is optional; dartnest injects required positional and '
        'required named parameters only.',
      );
    }
    final inject = Annotations.find(parameter, 'Inject');
    if (inject != null) return _tokenDependency(owner, parameter, inject);
    if (!_isInjectable(parameter.type)) {
      return _invalid(
        parameter,
        '$where has type ${parameter.type.getDisplayString()}; dartnest '
        'injects non-nullable class types, or a Token with @Inject(token).',
      );
    }
    return _injected(parameter, TypeKey(TypeReader.read(parameter.type)));
  }

  DependencyModel _tokenDependency(
    ClassElement owner,
    FormalParameterElement parameter,
    DartObject inject,
  ) {
    final where = _where(owner, parameter);
    final token = TokenReader.read(Annotations.field(inject, 'token'));
    if (token == null) {
      return _invalid(
        parameter,
        'The @Inject argument of $where is not a Token.',
      );
    }
    final (key, valueType) = token;
    if (!owner.library.typeSystem.isAssignableTo(valueType, parameter.type)) {
      return _invalid(
        parameter,
        '$where has type ${parameter.type.getDisplayString()}, but '
        '${key.display} provides ${key.valueType.display}.',
      );
    }
    return _injected(parameter, key);
  }

  static String _where(ClassElement owner, FormalParameterElement parameter) =>
      'Parameter ${parameter.displayName} of ${owner.displayName}';

  DependencyModel _invalid(FormalParameterElement parameter, String problem) =>
      DependencyModel.invalid(
        name: parameter.displayName,
        isNamed: parameter.isNamed,
        location: locations.of(parameter),
        problem: problem,
      );

  DependencyModel _injected(
    FormalParameterElement parameter,
    ProviderKey key,
  ) => DependencyModel.injected(
    name: parameter.displayName,
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
    key: key,
  );

  static bool _isInjectable(DartType type) =>
      type is InterfaceType &&
      type.nullabilitySuffix == NullabilitySuffix.none &&
      !type.isDartCoreObject;
}
