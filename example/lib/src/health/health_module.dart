import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'health_controller.dart';

/// The health check; its `appName` comes from the global `ConfigModule`.
@Module(id: 'health', controllers: [HealthController])
final class HealthModule {}
