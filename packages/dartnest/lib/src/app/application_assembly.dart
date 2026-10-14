import '../di/container.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../routing/router.dart';
import 'route_table_builder.dart';

/// The started container of an application and the route table built from
/// it.
typedef Assembly = ({Container container, Router<Endpoint> router});

/// Builds what an `Application` serves from its root module: validates the
/// routes before any provider is created, starts the container, creates the
/// controllers and the route table.
abstract final class ApplicationAssembly {
  /// Assembles [root] with the application-level [enhancers].
  ///
  /// Fails fast: a `RoutingError` before any provider is created; on any
  /// later failure the container is closed before the error is passed on.
  static Future<Assembly> start(Module root, Enhancers enhancers) async {
    RouteTableBuilder.validate(ModuleGraph.build(root));
    final container = await Container.create(root);
    // Any failure before the return closes the container; the error itself
    // propagates untouched, so no catch is needed.
    var succeeded = false;
    try {
      final router = RouteTableBuilder.build(container, enhancers);
      succeeded = true;
      return (container: container, router: router);
    } finally {
      if (!succeeded) await container.close();
    }
  }
}
