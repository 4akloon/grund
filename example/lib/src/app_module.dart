import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'app_module.g.dart';
import 'config/config_module.dart';
import 'health/health_module.dart';
import 'tasks/tasks_module.dart';

/// The application: what it does, not how it is served. `ServingModule`
/// adds the HTTP server and the adapter around it.
@Module(imports: [ConfigModule(), TasksModule(), HealthModule()])
final class AppModule extends grund.Module with $AppModule {
  /// Creates the module.
  const AppModule();
}
