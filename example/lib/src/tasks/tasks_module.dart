import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import '../auth/auth_module.dart';
import 'in_memory_task_store.dart';
import 'task_not_found_hook.dart';
import 'task_store.dart';
import 'tasks_api.dart';
import 'tasks_module.g.dart';
import 'tasks_service.dart';

/// Tasks: the store, the service, the API and its error hook; the pages
/// read [TasksService].
@Module(
  imports: [AuthModule()],
  providers: [
    Bind<TaskStore, InMemoryTaskStore>(),
    TasksService,
    TaskNotFoundHook,
    TasksApi,
  ],
  exports: [TasksService],
)
final class TasksModule extends grund.Module with $TasksModule {
  /// Creates the module.
  const TasksModule();
}
