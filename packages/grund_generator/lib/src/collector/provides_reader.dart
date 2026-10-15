import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/provides_model.dart';
import 'annotations.dart';
import 'dependency_reader.dart';
import 'lifetime_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads the `@Provides` methods of a class.
final class ProvidesReader {
  /// Creates the reader.
  ProvidesReader(this.locations) : _dependencies = DependencyReader(locations);

  /// Locations of methods and parameters.
  final SourceLocations locations;

  final DependencyReader _dependencies;

  /// The `@Provides` methods of [owner], in declaration order.
  List<ProvidesModel> read(ClassElement owner) => [
    for (final method in owner.methods)
      if (Annotations.find(method, 'Provides') case final annotation?)
        _read(owner, method, annotation),
  ];

  ProvidesModel _read(
    ClassElement owner,
    MethodElement method,
    DartObject annotation,
  ) {
    final name = '${owner.displayName}.${method.displayName}';
    final provided = _provided(method.returnType);
    final problem = _problem(method, name, provided);
    return ProvidesModel(
      owner: TypeReader.read(owner.thisType),
      methodName: method.displayName,
      location: locations.of(method),
      key: problem != null || provided == null
          ? null
          : BindingKey(TypeReader.read(provided), Annotations.named(method)),
      lifetime: LifetimeReader.read(annotation),
      isAsync: _isAsync(method.returnType),
      dependencies: [
        for (final parameter in method.formalParameters)
          _dependencies.read(parameter, name),
      ],
      documentation: method.documentationComment,
      problem: problem,
    );
  }

  /// The `T` of `T`, `Future<T>` and `FutureOr<T>`; `null` when the type is
  /// not a non-nullable class type.
  static InterfaceType? _provided(DartType returned) {
    final type = _isAsync(returned) && returned is InterfaceType
        ? returned.typeArguments.single
        : returned;
    return type is InterfaceType &&
            type.nullabilitySuffix == NullabilitySuffix.none &&
            !type.isDartCoreObject
        ? type
        : null;
  }

  static bool _isAsync(DartType type) =>
      type.isDartAsyncFuture || type.isDartAsyncFutureOr;

  static String? _problem(
    MethodElement method,
    String name,
    InterfaceType? provided,
  ) {
    if (!method.isStatic) return '@Provides method $name is not static.';
    if (method.isPrivate) return '@Provides method $name is private.';
    if (method.typeParameters.isNotEmpty) {
      return '@Provides method $name is generic.';
    }
    if (provided == null) {
      return '@Provides method $name returns '
          '${method.returnType.getDisplayString()}; it must return a '
          'non-nullable class type, or a Future of one.';
    }
    return null;
  }
}
