// Reads Environment without importing EnvironmentModule.
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

/// Needs the environment but does not import its module.
@Module()
final class NoImportModule extends grund.Module {
  /// Creates the module.
  const NoImportModule();

  /// Reads `NAME`.
  @Provides()
  static String name(grund.Environment environment) =>
      environment.string('NAME', fallback: 'world');
}
