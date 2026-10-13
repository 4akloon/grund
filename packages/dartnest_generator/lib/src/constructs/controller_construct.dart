import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/controller_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'controller_check.dart';

/// Checks controllers and their handlers and generates one function per
/// `@Controller` class.
final class ControllerConstruct implements Construct {
  /// Creates the construct.
  const ControllerConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => [
    for (final controller in package.controllers)
      ...ControllerCheck.check(controller),
    ..._duplicateRoutes(package),
  ];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final controller in package.controllers)
      DartUnit(
        name: GeneratedNames.controller(controller.type.name),
        spec: ControllerEmitter.function(controller),
        origin: controller.location,
      ),
  ];

  /// Routes with the same method and path shape across the package; path
  /// parameter names do not distinguish routes.
  static Iterable<Diagnostic> _duplicateRoutes(PackageModel package) sync* {
    final first = <String, String>{};
    for (final controller in package.controllers) {
      for (final route in controller.routes) {
        if (route.problem != null) continue;
        final full = ControllerCheck.fullPath(controller, route);
        final shape = full.path.replaceAll(RegExp(r':[^/]*'), ':');
        final handler = '${controller.type.name}.${route.handlerName}';
        final existing = first.putIfAbsent(
          '${route.method} $shape',
          () => handler,
        );
        if (existing != handler) {
          yield Diagnostic(
            DiagnosticCode.duplicateRoute,
            route.location,
            'Route ${route.method} ${full.path} is declared twice: by '
            '$existing and by $handler. Parameter names do not distinguish '
            'routes.',
          );
        }
      }
    }
  }
}
