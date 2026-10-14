/// Thrown by `TasksService` for an id no task has.
final class TaskNotFound implements Exception {
  /// Creates the error.
  const TaskNotFound(this.id);

  /// The unknown id.
  final int id;

  @override
  String toString() => 'TaskNotFound($id)';
}
