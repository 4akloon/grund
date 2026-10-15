import '../api/http_api.dart';
import '../api/route.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';

/// A route as the server holds it: the route, the API it belongs to and the
/// hooks around it, outermost first.
final class RouteEntry {
  /// Creates the entry.
  const RouteEntry({
    required this.api,
    required this.route,
    required this.hooks,
    required this.source,
  });

  /// The API the route belongs to.
  final HttpApi api;

  /// The route.
  final Route route;

  /// Global, API and route hooks, in that order.
  final List<HookRef<HttpHook>> hooks;

  /// Names the route in errors: `UsersApi.GET /:id`.
  final String source;
}
