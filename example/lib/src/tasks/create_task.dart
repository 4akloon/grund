/// The body of `POST /tasks`.
final class CreateTask {
  /// Creates the body.
  const CreateTask(this.title);

  /// Reads the body: the title is trimmed, then it must have 1 to
  /// [maxTitleLength] characters. Anything else is a [FormatException],
  /// which `HttpCtx.body` answers with 400.
  factory CreateTask.fromJson(Map<String, Object?> json) => switch (json) {
    {'title': final String title}
        when title.trim().isNotEmpty && title.trim().length <= maxTitleLength =>
      CreateTask(title.trim()),
    _ => throw const FormatException(
      '"title" must be a string of 1 to $maxTitleLength characters',
    ),
  };

  /// The longest accepted title.
  static const maxTitleLength = 200;

  /// What to do.
  final String title;
}
