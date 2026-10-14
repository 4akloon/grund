import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../config/config_module.dart';

/// `GET /health`, public: whether the application answers.
@Controller('/health')
final class HealthController {
  /// Reports [name].
  HealthController(@Inject(appName) this.name);

  /// The application name from the configuration.
  final String name;

  /// The status and the application name.
  @Get()
  Map<String, String> check() => {'status': 'ok', 'name': name};
}
