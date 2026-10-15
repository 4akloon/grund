import 'package:grund_annotations/grund_annotations.dart';

import 'create_task_dto.dart';
import 'task.dart';
import 'task_not_found.dart';
import 'task_store.dart';
import 'update_task_dto.dart';

/// The task use cases; knows nothing about HTTP.
@Injectable()
final class TasksService {
  /// Works on [store].
  TasksService(this.store);

  /// Where the tasks live.
  final TaskStore store;

  /// Every task, or only those whose state is [done].
  List<Task> list({bool? done}) => [
    for (final task in store.all())
      if (done == null || task.done == done) task,
  ];

  /// The task [id]; throws [TaskNotFound].
  Task find(int id) => store.find(id) ?? (throw TaskNotFound(id));

  /// Adds a task.
  Task create(CreateTaskDto dto) => store.add(dto.title);

  /// Changes the fields of task [id] that [dto] gives; throws
  /// [TaskNotFound].
  Task update(int id, UpdateTaskDto dto) {
    final task = find(id).copyWith(title: dto.title, done: dto.done);
    store.replace(task);
    return task;
  }

  /// Deletes task [id]; throws [TaskNotFound].
  void delete(int id) {
    if (!store.remove(id)) throw TaskNotFound(id);
  }
}
