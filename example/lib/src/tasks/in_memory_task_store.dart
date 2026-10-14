import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'task.dart';
import 'task_store.dart';

/// A [TaskStore] in memory, starting with two tasks. Its state survives a
/// hot reload, because dartnest keeps provider instances.
@Injectable()
final class InMemoryTaskStore implements TaskStore {
  final Map<int, Task> _tasks = {
    1: const Task(id: 1, title: 'Read the dartnest README'),
    2: const Task(id: 2, title: 'Run dartnest dev', done: true),
  };
  int _lastId = 2;

  // Ids only grow and a replaced task keeps its place, so insertion order
  // is id order.
  @override
  List<Task> all() => List.unmodifiable(_tasks.values);

  @override
  Task? find(int id) => _tasks[id];

  @override
  Task add(String title) {
    final task = Task(id: ++_lastId, title: title);
    _tasks[task.id] = task;
    return task;
  }

  @override
  bool replace(Task task) {
    if (!_tasks.containsKey(task.id)) return false;
    _tasks[task.id] = task;
    return true;
  }

  @override
  bool remove(int id) => _tasks.remove(id) != null;
}
