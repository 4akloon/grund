import '../api/http_api.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';
import '../routing/route_pattern.dart';
import '../routing/router.dart';
import 'route_entry.dart';
import 'route_table.dart';

/// Builds the [RouteTable] from the `HttpApi`s of the application.
abstract final class RouteTableBuilder {
  /// Registers every route of [apis] and checks that every hook can be
  /// resolved, so that a mistake surfaces before the server listens.
  ///
  /// Throws `InvalidRoutePatternError` for a bad path, `DuplicateRouteError`
  /// when two routes (also of different APIs) share a method and a path, and
  /// the resolution error (`MissingProviderError`, `ProviderCreationError`)
  /// of a hook that cannot be created. Hook types are resolved in a call
  /// scope of the API's module, as they are for a request, and that scope is
  /// closed again.
  static Future<RouteTable> build(
    List<HttpApi> apis,
    List<HookRef<HttpHook>> globalHooks,
  ) async {
    final router = Router<RouteEntry>();
    final routes = <String>[];
    final entries = <HttpApi, List<RouteEntry>>{};
    for (final api in apis) {
      for (final route in api.routes) {
        final pattern = RoutePattern.join(api.path, route.path);
        final entry = RouteEntry(
          api: api,
          route: route,
          hooks: [...globalHooks, ...api.use, ...route.use],
          source: '${api.runtimeType}.${route.name}',
        );
        router.add(route.method, pattern, entry, source: entry.source);
        routes.add('${route.method} $pattern');
        (entries[api] ??= []).add(entry);
      }
    }
    for (final MapEntry(key: api, value: apiEntries) in entries.entries) {
      await _checkHooks(api, apiEntries);
    }
    return RouteTable(router, List.unmodifiable(routes..sort()));
  }

  static Future<void> _checkHooks(HttpApi api, List<RouteEntry> entries) async {
    final scope = api.injector.openCall();
    try {
      for (final entry in entries) {
        for (final ref in entry.hooks) {
          ref.resolve(scope);
        }
      }
    } finally {
      await scope.close();
    }
  }
}
