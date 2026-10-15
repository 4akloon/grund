/// Declares an HTTP API class; the generator writes the `HttpApi` subclass
/// `<Name>Routes` and a binding for it next to the binding of the class.
///
/// The class is created through its unnamed constructor, like an
/// `Injectable`, and listed in `Module.providers`. Methods annotated with
/// `Get`, `Post`, `Put`, `Patch` or `Delete` become routes.
///
/// ```dart
/// @Api('/tasks', use: [ApiKeyHook])
/// final class TasksApi {
///   TasksApi(this.service);
///   final TasksService service;
///
///   @Get('/:id')
///   Future<Task> find(@Path() int id) => service.find(id);
/// }
/// ```
final class Api {
  /// Creates the annotation with the path prefix of every route and the
  /// [use] hooks of every route.
  const Api(this.path, {this.use = const []});

  /// Path prefix of every route.
  final String path;

  /// The hooks run for every route of the API, in order. An entry is one of:
  ///
  /// - a hook class, `ApiKeyHook`: resolved from the module graph, so the
  ///   module must provide it;
  /// - a constant hook instance, `RolesHook(Role.editor)`: its class needs a
  ///   `const` constructor;
  /// - a `HookRef` constant (`grund_http`), as in the explicit API.
  ///
  /// The generator turns each form into the same `HookRef`.
  final List<Object> use;
}
