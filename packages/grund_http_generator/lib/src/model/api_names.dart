/// Names of the declarations and files generated for `@Api` classes.
abstract final class ApiNames {
  /// The `HttpApi` subclass of `@Api` class [className]: `TasksApi` →
  /// `TasksApiRoutes`.
  static String routes(String className) => '${className}Routes';

  /// The part file of the source library at [sourcePath] (relative to the
  /// package root, with `/` separators): `lib/a.dart` → `lib/a.api.g.dart`.
  static String partPath(String sourcePath) {
    final stem = sourcePath.endsWith('.dart')
        ? sourcePath.substring(0, sourcePath.length - '.dart'.length)
        : sourcePath;
    return '$stem.api.g.dart';
  }
}
