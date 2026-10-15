import '../diagnostic/diagnostic.dart';
import '../diagnostic/http_diagnostic_codes.dart';
import '../diagnostic/source_location.dart';
import '../model/http_package_model.dart';
import 'route_paths.dart';

/// Finds routes of a package that answer the same requests.
abstract final class RouteConflictCheck {
  /// One diagnostic for every route of [http] after the first of the same
  /// method and path shape, in package order.
  static Iterable<Diagnostic> check(HttpPackageModel http) sync* {
    final first = <String, SourceLocation>{};
    for (final api in http.apis) {
      for (final route in api.routes) {
        if (route.problem != null) continue;
        final path = RoutePaths.join(api.path, route.path);
        final id = '${route.method} ${RoutePaths.shape(path)}';
        final other = first.putIfAbsent(id, () => route.location);
        if (other == route.location) continue;
        yield Diagnostic(
          HttpDiagnosticCodes.duplicateRoute,
          route.location,
          '${route.method} $path is already handled at $other. Change the '
          'method or the path of one of them.',
        );
      }
    }
  }
}
