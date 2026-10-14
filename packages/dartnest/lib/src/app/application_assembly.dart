import '../di/container.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../pipeline/enhancers.dart';
import 'assembly.dart';
import 'reassemble_report.dart';
import 'route_table_builder.dart';

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
      return Assembly(container: container, router: router);
    } finally {
      if (!succeeded) await container.close();
    }
  }

  /// Assembles [root] again after a hot reload, like [start] but through
  /// `Container.reassemble`, so providers that stay keep their instances;
  /// reports which routes changed against [current].
  ///
  /// [current] is not changed: on a failure it still serves.
  ///
  /// Neither container is closed: they share kept instances. When providers
  /// get shutdown hooks, dispose only the instances the dropped container
  /// created that the live one does not hold.
  static Future<(Assembly, ReassembleReport)> rebuild(
    Assembly current,
    Module root,
    Enhancers enhancers,
  ) async {
    final graph = ModuleGraph.build(root);
    RouteTableBuilder.validate(graph);
    final container = await current.container.reassemble(root);
    final router = RouteTableBuilder.build(container, enhancers);
    final report = ReassembleReport.between(
      RouteTableBuilder.describe(current.container.graph),
      RouteTableBuilder.describe(graph),
    );
    return (Assembly(container: container, router: router), report);
  }
}
