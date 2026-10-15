/// Names of the declarations and files the core generator emits, derived
/// from class names and source paths.
///
/// `UsersModule` → the mixin `$UsersModule`, written into the library
/// `users.g.dart` next to `users.dart`. Another package's module is not
/// imported by this library: its mixin is applied in its own source.
abstract final class GeneratedNames {
  /// The file name ending of generated files: `X.g.dart` for `x.dart`.
  static const outputSuffix = '.g.dart';

  /// The mixin of `@Module` class [className].
  static String module(String className) => '\$$className';

  /// The generated file of the source library at [sourcePath] (relative to
  /// the package root, with `/` separators): `lib/a.dart` → `lib/a.g.dart`.
  ///
  /// One fixed suffix, whatever the library declares: build_runner declares
  /// its outputs per input, so two outputs of one input could not share a
  /// stem. What the file is (a library with the mixins of the modules, or a
  /// part with other constructs' code) follows from the units written into
  /// it, and a library cannot need both.
  static String outputPath(String sourcePath) {
    final stem = sourcePath.endsWith('.dart')
        ? sourcePath.substring(0, sourcePath.length - '.dart'.length)
        : sourcePath;
    return '$stem$outputSuffix';
  }
}
