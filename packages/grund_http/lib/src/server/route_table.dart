import '../routing/route_match.dart';
import '../routing/router.dart';
import 'route_entry.dart';

/// Every route of the application, ready to match requests. Immutable: a hot
/// reload builds a new table and swaps it in.
final class RouteTable {
  /// Wraps the filled [router]; [routes] describes it.
  const RouteTable(this._router, this.routes);

  final Router<RouteEntry> _router;

  /// The routes as `'GET /users/:id'`, sorted.
  final List<String> routes;

  /// Finds the route for [method] and the decoded path [segments].
  RouteMatch<RouteEntry> match(String method, List<String> segments) =>
      _router.match(method, segments);
}
