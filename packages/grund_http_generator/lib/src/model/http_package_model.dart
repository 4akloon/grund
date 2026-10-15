import 'package:grund_generator/grund_generator.dart';

import 'api_host.dart';
import 'api_model.dart';
import 'dto_model.dart';
import 'route_model.dart';

/// What `ApiConstruct` collected from a package: its `@Api` classes, the
/// route methods outside them and the request and response bodies.
final class HttpPackageModel implements ExtensionModel {
  /// Creates the model.
  const HttpPackageModel({
    this.apis = const [],
    this.strayRoutes = const [],
    this.dtos = const [],
    this.hosts = const [],
  });

  /// Classes annotated with `@Api`, in library-URI order, then source order
  /// within a library.
  final List<ApiModel> apis;

  /// Route methods of classes that are not annotated with `@Api`.
  final List<RouteModel> strayRoutes;

  /// Request bodies and handler results, sorted by library URI, then name.
  final List<DtoModel> dtos;

  /// The libraries that declare `@Api` classes, in library-URI order.
  final List<ApiHost> hosts;

  /// Whether the package has no `@Api` class.
  @override
  bool get isEmpty => apis.isEmpty;
}
