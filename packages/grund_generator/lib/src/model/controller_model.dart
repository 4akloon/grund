import '../diagnostic/source_location.dart';
import 'constant_value.dart';
import 'constructor_model.dart';
import 'enhancers_model.dart';
import 'route_model.dart';
import 'type_model.dart';

/// A class annotated with `@Controller`.
final class ControllerModel {
  /// Creates the model.
  const ControllerModel({
    required this.type,
    required this.path,
    required this.constructor,
    required this.location,
    this.enhancers = const EnhancersModel(),
    this.metadata = const [],
    this.routes = const [],
    this.documentation,
  });

  /// The controller class.
  final TypeModel type;

  /// The path prefix of every route.
  final String path;

  /// How to create the instance.
  final ConstructorModel constructor;

  /// Where the class is declared.
  final SourceLocation location;

  /// Controller-level components.
  final EnhancersModel enhancers;

  /// Controller-level `RouteMetadata` annotations.
  final List<ConstantValue> metadata;

  /// The routes, in declaration order.
  final List<RouteModel> routes;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
