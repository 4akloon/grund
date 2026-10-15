import 'package:logging/logging.dart';

/// The startup and shutdown messages of the `HttpServer`: the routes on
/// `grund.routes`, the listener on `grund.http`.
final class ServerLog {
  /// Creates the log.
  const ServerLog();

  /// Logged when the server stopped after it had listened.
  static const closedMessage = 'HTTP server closed';

  static final Logger _routes = Logger('grund.routes');
  static final Logger _http = Logger('grund.http');

  /// The text of the route `'GET /tasks'`: `Mapped {GET, /tasks}`.
  static String mappedMessage(String route) => 'Mapped ${_braced(route)}';

  /// The text of the route `'GET /tasks'`: `Unmapped {GET, /tasks}`.
  static String unmappedMessage(String route) => 'Unmapped ${_braced(route)}';

  /// Logs `Mapped {METHOD, path}` for each of [routes].
  void mapped(Iterable<String> routes) {
    for (final route in _byPath(routes)) {
      _routes.info(mappedMessage(route));
    }
  }

  /// Logs `Unmapped {METHOD, path}` for each of [routes].
  void unmapped(Iterable<String> routes) {
    for (final route in _byPath(routes)) {
      _routes.info(unmappedMessage(route));
    }
  }

  /// Logs where the server listens.
  void listening(Object address, int port) =>
      _http.info('HTTP server listening on $address:$port');

  /// Logs that the server stopped.
  void closed() => _http.info(closedMessage);

  // Routes are 'METHOD /path'; the order is by path, then method.
  static List<String> _byPath(Iterable<String> routes) =>
      routes.toList()..sort((a, b) {
        final byPath = _path(a).compareTo(_path(b));
        return byPath != 0 ? byPath : a.compareTo(b);
      });

  static String _path(String route) => route.substring(route.indexOf(' ') + 1);

  static String _braced(String route) {
    final space = route.indexOf(' ');
    return '{${route.substring(0, space)}, ${route.substring(space + 1)}}';
  }
}
