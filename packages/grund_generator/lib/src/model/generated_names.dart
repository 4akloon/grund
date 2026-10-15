/// Names of the declarations the generator emits, derived from class names.
///
/// `UsersModule` → the mixin `$UsersModule`, `TasksApi` → the `HttpApi`
/// subclass `TasksApiRoutes`. Another package's module is not imported by
/// this library: its mixin is applied in its own source.
abstract final class GeneratedNames {
  /// The mixin of `@Module` class [className].
  static String module(String className) => '\$$className';

  /// The `HttpApi` subclass of `@Api` class [className].
  static String routes(String className) => '${className}Routes';

  /// The generated library of package [packageName].
  static String library(String packageName) =>
      'package:$packageName/$packageName.grund.dart';
}
