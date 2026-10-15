import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/api_model.dart';
import '../model/http_package_model.dart';
import '../model/route_model.dart';
import 'api_reader.dart';
import 'dto_reader.dart';
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
    final dtoRoots = <DartType>[];
    for (final library in context.libraries) {
      for (final element in library.classes) {
        if (Annotations.find(element, 'Api') case final api?) {
          apiModels.add(apis.read(element, api));
          dtoRoots.addAll(_dtoRoots(element));
        } else {
          strayRoutes.addAll(routes.read(element));
        }
      }
    }
    return HttpPackageModel(
      apis: apiModels,
      strayRoutes: strayRoutes,
      dtos: DtoReader.read(dtoRoots),
    );
  }

  static List<DartType> _dtoRoots(ClassElement api) => [
    for (final method in api.methods)
      if (Annotations.all(method, RouteReader.annotations).isNotEmpty) ...[
        method.returnType,
        for (final parameter in method.formalParameters)
          if (Annotations.find(parameter, 'Body') != null) parameter.type,
      ],
  ];
}
