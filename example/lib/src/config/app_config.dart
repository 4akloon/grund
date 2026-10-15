import '../auth/role.dart';

/// The application name and the API keys, with the role each one grants.
final class AppConfig {
  /// Creates the configuration.
  const AppConfig({required this.name, required this.apiKeys});

  /// The configuration of the example; a real application reads the keys
  /// from a secret store.
  static const demo = AppConfig(
    name: 'tasks_api',
    apiKeys: {'reader-key': Role.reader, 'editor-key': Role.editor},
  );

  /// The name the health check reports.
  final String name;

  /// The role each API key grants.
  final Map<String, Role> apiKeys;
}
