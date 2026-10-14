import 'create_task_dto.dart';

/// The body of `PATCH /tasks/:id`: the fields to change.
final class UpdateTaskDto {
  /// Creates the body.
  const UpdateTaskDto({this.title, this.done});

  /// Reads the body; a field of the wrong type is a [FormatException]
  /// (400).
  factory UpdateTaskDto.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final done = json['done'];
    final validTitle =
        title == null ||
        title is String &&
            title.isNotEmpty &&
            title.length <= CreateTaskDto.maxTitleLength;
    if (!validTitle || (done != null && done is! bool)) {
      throw const FormatException(
        '"title" must be a non-empty string and "done" a boolean',
      );
    }
    return UpdateTaskDto(title: title as String?, done: done as bool?);
  }

  /// The new title, or `null` to keep it.
  final String? title;

  /// The new state, or `null` to keep it.
  final bool? done;
}
