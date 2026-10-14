import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../auth/auth_module.dart';
import '../common/trim_strings_pipe.dart';
import 'in_memory_task_store.dart';
import 'task_not_found_filter.dart';
import 'task_store.dart';
import 'tasks_controller.dart';
import 'tasks_service.dart';

/// Tasks: the store, the service, the controller and its components.
@Module(
  id: 'tasks',
  imports: [AuthModule],
  providers: [
    Bind<TaskStore, InMemoryTaskStore>(),
    TasksService,
    TrimStringsPipe,
    TaskNotFoundFilter,
  ],
  controllers: [TasksController],
)
final class TasksModule {}
