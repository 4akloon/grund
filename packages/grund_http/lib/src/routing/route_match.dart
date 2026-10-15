/// Result of `Router.match`.
sealed class RouteMatch<V> {
  /// Creates a result.
  const RouteMatch();
}

/// A route matches the path and the method.
final class RouteFound<V> extends RouteMatch<V> {
  /// Creates the result.
  const RouteFound(this.value, this.parameters);

  /// The value registered for the route.
  final V value;

  /// Path parameters by name (the wildcard as `*`), percent-decoded.
  final Map<String, String> parameters;
}

/// Some route matches the path, none matches the method.
final class RouteMethodNotAllowed<V> extends RouteMatch<V> {
  /// Creates the result.
  const RouteMethodNotAllowed(this.allowed);

  /// Methods accepted for the path, sorted; `HEAD` is included when `GET`
  /// is.
  final List<String> allowed;
}

/// No route matches the path.
final class RouteNotFound<V> extends RouteMatch<V> {
  /// Creates the result.
  const RouteNotFound();
}
