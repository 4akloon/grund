/// Configuration every module sees: the application name and the API keys.
///
/// The tokens and the demo keys sit beside [ConfigModule] on purpose: the
/// module's own `providers` list refers to them, and the other modules import
/// the tokens from the same place.
library;

import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../auth/role.dart';

/// The name the health check reports.
const appName = Token<String>('config.app_name');

/// The API keys and the role each one grants.
const apiKeys = Token<Map<String, Role>>('config.api_keys');

/// The keys of the example; a real application reads them from a secret
/// store.
const demoApiKeys = {'reader-key': Role.reader, 'editor-key': Role.editor};

/// Configuration values, visible in every module (`global: true`).
@Module(
  id: 'config',
  providers: [
    Value('tasks_api', token: appName),
    Value(demoApiKeys, token: apiKeys),
  ],
  exports: [appName, apiKeys],
  global: true,
)
final class ConfigModule {}
