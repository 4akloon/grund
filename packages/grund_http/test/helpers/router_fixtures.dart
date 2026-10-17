import 'package:grund_http/src/routing/route_match.dart';
import 'package:grund_http/src/routing/route_pattern.dart';
import 'package:grund_http/src/routing/router.dart';
import 'package:test/test.dart';

Router<String> routerOf(List<(String, String)> routes) {
  final router = Router<String>();
  for (final (method, path) in routes) {
    router.add(
      method,
      RoutePattern.join('', path),
      '$method $path',
      source: '$method $path',
    );
  }
  return router;
}

List<String> split(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList();

RouteMatch<String> match(Router<String> router, String method, String path) =>
    router.match(method, split(path));

Matcher found(String value, [Map<String, String> parameters = const {}]) =>
    isA<RouteFound<String>>()
        .having((m) => m.value, 'value', value)
        .having((m) => m.parameters, 'parameters', parameters);
