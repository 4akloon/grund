import '../diagnostic/source_location.dart';
import 'constant_value.dart';
import 'enhancers_model.dart';
import 'handler_parameter.dart';
import 'type_model.dart';

/// A controller method annotated with `@Get`, `@Post`, `@Put`, `@Patch` or
/// `@Delete`.
final class RouteModel {
  /// Creates the model.
  const RouteModel({
    required this.method,
    required this.path,
    required this.handlerName,
    required this.returnType,
    required this.location,
    this.parameters = const [],
    this.enhancers = const EnhancersModel(),
    this.metadata = const [],
    this.documentation,
    this.problem,
  });

  /// The upper-cased HTTP method.
  final String method;

  /// The path relative to the controller path.
  final String path;

  /// The method name.
  final String handlerName;

  /// The declared return type.
  final TypeModel returnType;

  /// Where the method is declared.
  final SourceLocation location;

  /// The parameters, in declaration order.
  final List<HandlerParameter> parameters;

  /// Route-level components.
  final EnhancersModel enhancers;

  /// Route-level `RouteMetadata` annotations.
  final List<ConstantValue> metadata;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot be a handler, as a sentence; `null` when it can.
  final String? problem;

  /// Names of the `:name` parameters and the `*` wildcard of [path].
  List<String> get pathParameters => [
    for (final segment in path.split('/'))
      if (segment.startsWith(':'))
        segment.substring(1)
      else if (segment == '*')
        '*',
  ];
}
