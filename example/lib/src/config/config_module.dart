import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'app_config.dart';
import 'config_module.g.dart';

/// The configuration every module sees: [global] makes its export visible
/// without an import.
@Module(global: true, exports: [AppConfig])
final class ConfigModule extends grund.Module with $ConfigModule {
  /// Creates the module.
  const ConfigModule();

  /// The configuration value; a `@Provides` method is a singleton.
  @Provides()
  static AppConfig appConfig() => AppConfig.demo;
}
