/// Makes a method of an `Api` class an HTTP route.
///
/// [path] is relative to the API path and may contain `:name` parameters and
/// a trailing `*`, as in the explicit `Route`.
sealed class RouteAnnotation {
  /// Creates the annotation for [method] and [path].
  const RouteAnnotation(this.method, this.path, this.status, this.use);

  /// The upper-cased HTTP method.
  final String method;

  /// Path relative to the API path.
  final String path;

  /// The response status; `null` leaves the default of the response.
  final int? status;

  /// `HookRef` constants (`grund_http`), run for this route after the hooks
  /// of the API.
  final List<Object> use;
}

/// A `GET` route.
final class Get extends RouteAnnotation {
  /// Creates the annotation.
  const Get(String path, {int? status, List<Object> use = const []})
    : super('GET', path, status, use);
}

/// A `POST` route.
final class Post extends RouteAnnotation {
  /// Creates the annotation.
  const Post(String path, {int? status, List<Object> use = const []})
    : super('POST', path, status, use);
}

/// A `PUT` route.
final class Put extends RouteAnnotation {
  /// Creates the annotation.
  const Put(String path, {int? status, List<Object> use = const []})
    : super('PUT', path, status, use);
}

/// A `PATCH` route.
final class Patch extends RouteAnnotation {
  /// Creates the annotation.
  const Patch(String path, {int? status, List<Object> use = const []})
    : super('PATCH', path, status, use);
}

/// A `DELETE` route.
final class Delete extends RouteAnnotation {
  /// Creates the annotation.
  const Delete(String path, {int? status, List<Object> use = const []})
    : super('DELETE', path, status, use);
}
