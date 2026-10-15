import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'health_api.dart';
import 'health_module.g.dart';

/// The health check; its `AppConfig` comes from the global `ConfigModule`.
@Module(providers: [HealthApi])
final class HealthModule extends grund.Module with $HealthModule {
  /// Creates the module.
  const HealthModule();
}
