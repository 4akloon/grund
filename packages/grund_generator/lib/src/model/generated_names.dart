/// Names of the declarations and files the core generator emits, derived
/// from class names and source paths.
///
/// `UsersModule` → the mixin `$UsersModule`, written into the library
/// `users_module.g.dart` next to `users.dart`. Another package's module is
/// not imported by this library: its mixin is applied in its own source.
abstract final class GeneratedNames {
  /// The mixin of `@Module` class [className].
  static String module(String className) => '\$$className';

  /// The generated module library of the source library at [sourcePath]
  /// (relative to the package root, with `/` separators): `lib/a.dart` →
  /// `lib/a_module.g.dart`.
  static String moduleLibraryPath(String sourcePath) {
    final stem = sourcePath.endsWith('.dart')
        ? sourcePath.substring(0, sourcePath.length - '.dart'.length)
        : sourcePath;
    return '${stem}_module.g.dart';
  }
}
