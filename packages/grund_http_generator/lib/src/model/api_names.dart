/// Names of the declarations generated for `@Api` classes.
abstract final class ApiNames {
  /// The `HttpApi` subclass of `@Api` class [className]: `TasksApi` →
  /// `TasksApiRoutes`.
  static String routes(String className) => '${className}Routes';
}
