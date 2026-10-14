import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'common/timing_interceptor.dart';
import 'config/config_module.dart';
import 'health/health_module.dart';
import 'tasks/tasks_module.dart';

/// The application root. [TimingInterceptor] is provided here because
/// application-level components resolve from the root module.
@Module(
  id: 'app',
  imports: [ConfigModule, TasksModule, HealthModule],
  providers: [TimingInterceptor],
)
final class AppModule {}
