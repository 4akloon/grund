/// Names of the declarations the core generator emits, derived from class
/// names.
///
/// `UsersModule` → the mixin `$UsersModule`. Another package's module is
/// not imported by this library: its mixin is applied in its own source.
abstract final class GeneratedNames {
  /// The mixin of `@Module` class [className].
  static String module(String className) => '\$$className';

  /// The generated library of package [packageName].
  static String library(String packageName) =>
      'package:$packageName/$packageName.grund.dart';

  /// The path of the generated library of package [packageName], relative
  /// to the package root.
  static String libraryPath(String packageName) =>
      'lib/$packageName.grund.dart';
}
