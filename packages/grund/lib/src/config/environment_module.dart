import 'dart:io' show Platform;

import '../di/binding.dart';
import '../di/key.dart';
import '../di/module.dart';
import 'environment.dart';

/// Binds the [Environment] of the process, visible to every module.
final class EnvironmentModule extends Module {
  /// Creates the module.
  const EnvironmentModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Environment>(
      (_) => Environment(Platform.environment),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<Environment>()];
}
