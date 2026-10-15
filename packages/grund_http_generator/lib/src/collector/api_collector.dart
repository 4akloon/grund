import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/api_host.dart';
import '../model/api_model.dart';
import '../model/http_package_model.dart';
import '../model/route_model.dart';
import 'api_host_reader.dart';
import 'api_reader.dart';
import 'dto_reader.dart';
import 'http_annotations.dart';
import 'route_reader.dart';

/// Reads the `@Api` classes of a package, the route methods outside them
/// and the bodies their routes take and return.
abstract final class ApiCollector {
  /// The model of the libraries of [context].
  static HttpPackageModel collect(CollectionContext context) {
    final routes = RouteReader(context.locations);
    final apis = ApiReader(context.locations, routes);
    final apiModels = <ApiModel>[];
    final strayRoutes = <RouteModel>[];
    final hosts = <ApiHost>[];
    final dtoRoots = <DartType>[];
    for (final library in context.libraries) {
      final declared = apiModels.length;
      for (final element in library.classes) {
        if (HttpAnnotations.reader.find(element, 'Api') case final api?) {
          apiModels.add(apis.read(element, api));
          dtoRoots.addAll(_dtoRoots(element));
        } else {
          strayRoutes.addAll(routes.read(element));
        }
      }
      if (apiModels.length > declared) {
        hosts.add(
          ApiHostReader.read(
            library,
            context.locations.pathOf(library),
            apiModels[declared].location,
          ),
        );
      }
    }
    return HttpPackageModel(
      apis: apiModels,
      strayRoutes: strayRoutes,
      dtos: DtoReader.read(dtoRoots),
      hosts: hosts,
    );
  }

  static List<DartType> _dtoRoots(ClassElement api) => [
    for (final method in api.methods)
      if (HttpAnnotations.reader
          .all(method, RouteReader.annotations)
          .isNotEmpty) ...[
        method.returnType,
        for (final parameter in method.formalParameters)
          if (HttpAnnotations.reader.find(parameter, 'Body') != null)
            parameter.type,
      ],
  ];
}
