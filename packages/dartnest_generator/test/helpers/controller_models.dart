import 'package:dartnest_generator/src/diagnostic/source_location.dart';
import 'package:dartnest_generator/src/model/body_kind.dart';
import 'package:dartnest_generator/src/model/component_reference.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/constructor_model.dart';
import 'package:dartnest_generator/src/model/controller_model.dart';
import 'package:dartnest_generator/src/model/dependency_model.dart';
import 'package:dartnest_generator/src/model/enhancers_model.dart';
import 'package:dartnest_generator/src/model/handler_parameter.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/parameter_binding.dart';
import 'package:dartnest_generator/src/model/provider_key.dart';
import 'package:dartnest_generator/src/model/route_model.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';

/// Builders of small hand-made controllers for the edge-case tests.
abstract final class ControllerModels {
  /// The location every model is declared at.
  static const location = SourceLocation('lib/app.dart', 3, 7);

  /// A class type named [name].
  static TypeModel type(String name, {bool isNullable = false}) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'package:app/app.dart',
    isNullable: isNullable,
  );

  /// A `dart:core` type named [name].
  static TypeModel core(String name, {bool isNullable = false}) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'dart:core',
    isNullable: isNullable,
  );

  /// A parameter named [name] of [type] with [binding].
  static HandlerParameter parameter(
    String name,
    TypeModel type,
    ParameterBinding binding, {
    bool isNamed = false,
  }) => HandlerParameter(
    name: name,
    type: type,
    binding: binding,
    isNamed: isNamed,
    location: location,
  );

  /// A body parameter read as [kind].
  static HandlerParameter body(BodyKind kind, TypeModel type) =>
      parameter('body', type, BodyBinding(kind));

  /// A route of [method] at [path].
  static RouteModel route(
    String method,
    String path, {
    String name = 'handle',
    TypeModel returnType = TypeModel.voidType,
    List<HandlerParameter> parameters = const [],
    List<ConstantValue> metadata = const [],
    EnhancersModel enhancers = const EnhancersModel(),
    String? problem,
  }) => RouteModel(
    method: method,
    path: path,
    handlerName: name,
    returnType: returnType,
    location: location,
    parameters: parameters,
    metadata: metadata,
    enhancers: enhancers,
    problem: problem,
  );

  /// A dependency on the class [name].
  static DependencyModel dependency(String name, {bool isNamed = false}) =>
      DependencyModel.injected(
        name: name.toLowerCase(),
        isNamed: isNamed,
        location: location,
        key: TypeKey(type(name)),
      );

  /// A controller [name] at [path].
  static ControllerModel controller(
    String name,
    String path,
    List<RouteModel> routes, {
    ConstructorModel constructor = const ConstructorModel([]),
    List<ConstantValue> metadata = const [],
    EnhancersModel enhancers = const EnhancersModel(),
  }) => ControllerModel(
    type: type(name),
    path: path,
    constructor: constructor,
    location: location,
    metadata: metadata,
    enhancers: enhancers,
    routes: routes,
  );

  /// A component [name] for an enhancer list.
  static ComponentReference component(String name) =>
      ComponentReference(type(name), isValid: true);

  /// A package of [controllers].
  static PackageModel package(List<ControllerModel> controllers) =>
      PackageModel(
        packageName: 'app',
        languageVersion: Version(3, 8, 0),
        controllers: controllers,
      );
}
