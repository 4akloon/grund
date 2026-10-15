import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import '../config/app_config.dart';

part 'health_api.g.dart';

/// `GET /health`, public: whether the application answers.
@Api('/health')
final class HealthApi {
  /// Reports the name from [config].
  HealthApi(this.config);

  /// The configuration.
  final AppConfig config;

  /// The status and the application name.
  @Get('/')
  Map<String, String> check() => {'status': 'ok', 'name': config.name};
}
