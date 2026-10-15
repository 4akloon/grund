/// Makes a controller method an HTTP route.
///
/// [path] is relative to the controller path and may contain `:name`
/// parameters and a trailing `*`, as in the explicit `Route`.
sealed class RouteAnnotation {
  /// Creates the annotation for [method] and [path].
  const RouteAnnotation(this.method, this.path);

  /// The upper-cased HTTP method.
  final String method;

  /// Path relative to the controller path.
  final String path;
}

/// A `GET` route.
final class Get extends RouteAnnotation {
  /// Creates the annotation.
  const Get([String path = '']) : super('GET', path);
}

/// A `POST` route.
final class Post extends RouteAnnotation {
  /// Creates the annotation.
  const Post([String path = '']) : super('POST', path);
}

/// A `PUT` route.
final class Put extends RouteAnnotation {
  /// Creates the annotation.
  const Put([String path = '']) : super('PUT', path);
}

/// A `PATCH` route.
final class Patch extends RouteAnnotation {
  /// Creates the annotation.
  const Patch([String path = '']) : super('PATCH', path);
}

/// A `DELETE` route.
final class Delete extends RouteAnnotation {
  /// Creates the annotation.
  const Delete([String path = '']) : super('DELETE', path);
}
