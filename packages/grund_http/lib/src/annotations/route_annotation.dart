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

  /// The hooks run for this route after the hooks of the API, in order. An
  /// entry is one of:
  ///
  /// - a hook class, `ApiKeyHook`: resolved from the module graph, so the
  ///   module must provide it;
  /// - a constant hook instance, `RolesHook(Role.editor)`: its class needs a
  ///   `const` constructor;
  /// - a `HookRef` constant (`grund_http`), as in the explicit API.
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
