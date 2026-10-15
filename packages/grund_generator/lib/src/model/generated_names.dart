/// Names of the declarations the generator emits, derived from class names.
///
/// `UsersModule` → `usersModule`, `Config` (a `@Module`) → `configModule`,
/// `UsersController` → `usersController`, `UsersService` →
/// `_createUsersService` (factories stay private to the generated library).
/// Another package's `@Module` class is imported by the same rule from that
/// package's `<package>.grund.dart`.
abstract final class GeneratedNames {
  /// The function that builds the module of `@Module` class [className].
  static String module(String className) => _suffixed(className, 'Module');

  /// The function that builds the controller of `@Controller` class
  /// [className].
  static String controller(String className) =>
      _suffixed(className, 'Controller');

  /// The private factory function of injectable class [className].
  static String factory(String className) => '_create$className';

  /// The generated library of package [packageName].
  static String library(String packageName) =>
      'package:$packageName/$packageName.grund.dart';

  static String _suffixed(String className, String suffix) {
    final name = className.endsWith(suffix) ? className : '$className$suffix';
    return '${name[0].toLowerCase()}${name.substring(1)}';
  }
}
