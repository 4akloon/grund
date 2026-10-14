import 'task.dart';

/// Where tasks live. The example binds it to `InMemoryTaskStore`; a real
/// application binds a database-backed class instead.
abstract interface class TaskStore {
  /// Every task, by id.
  List<Task> all();

  /// The task [id], or `null`.
  Task? find(int id);

  /// Stores a new task titled [title] and returns it.
  Task add(String title);

  /// Replaces the stored task with the same id; returns whether it existed.
  bool replace(Task task);

  /// Removes the task [id]; returns whether it existed.
  bool remove(int id);
}
