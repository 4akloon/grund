import 'package:grund_annotations/grund_annotations.dart';

import 'health_controller.dart';

/// The health check; its `appName` comes from the global `ConfigModule`.
@Module(id: 'health', controllers: [HealthController])
final class HealthModule {}
