// A module that provides an API and its service.
import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';

import '../apis/tasks.dart';

/// Hooks and the API.
@Module(providers: [TasksApi, ApiKeyHook])
final class TasksModule extends grund.Module {
  /// Creates the module.
  const TasksModule();

  /// Where tasks live.
  @Provides()
  static Map<int, Task> store() => {};
}
