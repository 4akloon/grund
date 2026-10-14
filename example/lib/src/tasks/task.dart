/// A task of the tasks API.
final class Task {
  /// Creates a task.
  const Task({required this.id, required this.title, this.done = false});

  /// The id the store assigned.
  final int id;

  /// What to do.
  final String title;

  /// Whether the task is done.
  final bool done;

  /// This task with [title] and [done] replaced where given.
  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);

  /// The JSON form; dartnest serializes results through `toJson()`.
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};
}
