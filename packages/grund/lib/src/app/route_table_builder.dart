import '../controller/controller.dart';
import '../di/container.dart';
import '../di/injector.dart';
import '../di/module_graph.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/resolved_enhancers.dart';
import '../routing/route_pattern.dart';
import '../routing/router.dart';

/// Turns the controllers of a module graph into a [Router] of [Endpoint]s.
///
/// Modules are visited in `ModuleGraph.ordered` order, controllers and
/// routes in declaration order, so duplicate reports are deterministic.
abstract final class RouteTableBuilder {
  /// Checks every route pattern and rejects duplicate routes without
  /// creating anything, so `Application.create` can fail before any provider
  /// factory runs. Throws a `RoutingError`.
  static void validate(ModuleGraph graph) {
    final dryRun = Router<void>();
    for (final module in graph.ordered) {
      for (final controller in module.controllers) {
        for (final route in controller.routes) {
          dryRun.add(
            route.method,
            RoutePattern.join(controller.path, route.path),
            null,
            source: _source(controller, route.name, module.id),
          );
        }
      }
    }
  }

  /// Every route of [graph] as `'GET /users/:id'`, sorted; nothing is
  /// created.
  static List<String> describe(ModuleGraph graph) => [
    for (final module in graph.ordered)
      for (final controller in module.controllers)
        for (final route in controller.routes)
          '${route.method} ${RoutePattern.join(controller.path, route.path)}',
  ]..sort();

  /// Creates every controller with its module's injector, resolves the
  /// application [enhancers] through the root injector and the controller
  /// and route enhancers through the controller's module injector, and
  /// registers one [Endpoint] per route.
  static Router<Endpoint> build(Container container, Enhancers enhancers) {
    final application = ResolvedEnhancers.resolve(
      enhancers,
      container.root,
      owner: 'Application',
    );
    final router = Router<Endpoint>();
    for (final module in container.graph.ordered) {
      final injector = container.injectorFor(module.id);
      for (final controller in module.controllers) {
        _addController(router, controller, injector, application);
      }
    }
    return router;
  }

  static void _addController(
    Router<Endpoint> router,
    ControllerSpec controller,
    Injector injector,
    ResolvedEnhancers application,
  ) {
    final instance = controller.instantiate(injector);
    final controllerLevel = ResolvedEnhancers.resolve(
      controller.enhancers,
      injector,
      owner: '${controller.type}',
    );
    for (final route in controller.routes) {
      final routeLevel = ResolvedEnhancers.resolve(
        route.enhancers,
        injector,
        owner: '${controller.type}.${route.name}',
      );
      final endpoint = Endpoint(
        controllerType: controller.type,
        handlerName: route.name,
        metadata: [...route.metadata, ...controller.metadata],
        enhancers: ResolvedEnhancers.chain([
          application,
          controllerLevel,
          routeLevel,
        ]),
        invoke: (context) => route.invoke(instance, context),
      );
      router.add(
        route.method,
        RoutePattern.join(controller.path, route.path),
        endpoint,
        source: _source(controller, route.name, injector.moduleId),
      );
    }
  }

  static String _source(
    ControllerSpec controller,
    String handler,
    String moduleId,
  ) => '${controller.type}.$handler (module "$moduleId")';
}
