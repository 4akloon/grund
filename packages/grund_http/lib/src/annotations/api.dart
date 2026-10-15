/// Declares an HTTP API class; the generator writes the `HttpApi` subclass
/// `<Name>Routes` and a binding for it next to the binding of the class.
///
/// The class is created through its unnamed constructor, like an
/// `Injectable`, and listed in `Module.providers`. Methods annotated with
/// `Get`, `Post`, `Put`, `Patch` or `Delete` become routes.
///
/// ```dart
/// @Api('/tasks', use: [HookRef<ApiKeyHook>.type()])
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

  /// `HookRef` constants (`grund_http`), run for every route of the API.
  final List<Object> use;
}
