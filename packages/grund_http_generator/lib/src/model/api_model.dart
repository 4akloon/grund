import 'package:grund_generator/grund_generator.dart';

import 'hook_model.dart';
import 'route_model.dart';

/// A class annotated with `@Api`.
///
/// Together with [RouteModel] and `ParamModel` this is everything an
/// OpenAPI description needs (types, `///` comments, validation
/// annotations); stage 2 builds its `ApiDescription` from it, stage 1 only
/// emits the routes.
final class ApiModel {
  /// Creates the model.
  const ApiModel({
    required this.type,
    required this.path,
    required this.location,
    required this.libraryPath,
    this.use = const [],
    this.routes = const [],
    this.invalidEntries = const [],
    this.documentation,
  });

  /// The API class.
  final TypeModel type;

  /// The path prefix of every route.
  final String path;

  /// Where the class is declared.
  final SourceLocation location;

  /// The package-relative path of the library that declares the class: the
  /// host of its generated part.
  final String libraryPath;

  /// Hooks of every route, in order.
  final List<HookModel> use;

  /// The routes, in declaration order.
  final List<RouteModel> routes;

  /// One sentence per `use` entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
