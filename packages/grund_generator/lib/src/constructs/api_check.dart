import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/api_model.dart';
import '../model/injectable_model.dart';
import '../model/lifetime.dart';
import '../model/package_model.dart';
import 'route_check.dart';
import 'route_paths.dart';

/// Checks the `@Api` classes of a package: how they are provided, their
/// hooks and each of their routes.
abstract final class ApiCheck {
  /// The problems of the apis of [package].
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    for (final api in package.apis) {
      yield* _provided(api, package);
      yield* _hooks(api);
      for (final route in api.routes) {
        yield* RouteCheck.check(route, RoutePaths.join(api.path, route.path));
      }
    }
    for (final route in package.strayRoutes) {
      yield Diagnostic(
        DiagnosticCode.routeOutsideApi,
        route.location,
        'Route ${route.handlerName} is in a class that is not annotated with '
        '@Api; it is never served.',
      );
    }
  }

  static Iterable<Diagnostic> _provided(
    ApiModel api,
    PackageModel package,
  ) sync* {
    final injectable = _injectable(api, package);
    if (injectable != null && injectable.lifetime != Lifetime.singleton) {
      yield Diagnostic(
        DiagnosticCode.invalidApi,
        api.location,
        '${api.type} is an @Api but its @Injectable has scope '
        '${injectable.lifetime.name}; an API is created once, so it must be '
        'a singleton.',
      );
    }
    final owners = [
      for (final module in package.modules)
        if (module.providers.any((p) => p.injectable.type == api.type))
          module.type.display,
    ];
    if (owners.length > 1) {
      yield Diagnostic(
        DiagnosticCode.duplicateApi,
        api.location,
        '${api.type} is provided by modules [${owners.join(', ')}]; its '
        'routes would be registered twice. Provide it in one module.',
      );
    }
  }

  static InjectableModel? _injectable(ApiModel api, PackageModel package) =>
      package.injectables.where((i) => i.type == api.type).firstOrNull;

  static Iterable<Diagnostic> _hooks(ApiModel api) sync* {
    for (final problem in api.invalidEntries) {
      yield Diagnostic(
        DiagnosticCode.invalidHook,
        api.location,
        'Api ${api.type}: $problem',
      );
    }
    yield* RouteCheck.hookConstants(api.use, api.location, '${api.type}');
  }
}
