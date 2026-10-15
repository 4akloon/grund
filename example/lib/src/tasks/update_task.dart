import 'create_task.dart';

/// The body of `PATCH /tasks/:id`: the fields to change.
final class UpdateTask {
  /// Creates the body.
  const UpdateTask({this.title, this.done});

  /// Reads the body; a field of the wrong type is a [FormatException]
  /// (400 from `HttpCtx.body`).
  factory UpdateTask.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final done = json['done'];
    final validTitle =
        title == null ||
        title is String &&
            title.trim().isNotEmpty &&
            title.trim().length <= CreateTask.maxTitleLength;
    if (!validTitle || (done != null && done is! bool)) {
      throw const FormatException(
        '"title" must be a non-empty string and "done" a boolean',
      );
    }
    return UpdateTask(title: (title as String?)?.trim(), done: done as bool?);
  }

  /// The new title, or `null` to keep it.
  final String? title;

  /// The new state, or `null` to keep it.
  final bool? done;
}
