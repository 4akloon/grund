/// The body of `POST /tasks`.
final class CreateTaskDto {
  /// Creates the body.
  const CreateTaskDto(this.title);

  /// Reads the body; a missing, empty or too long title is a
  /// [FormatException], which dartnest answers with 400.
  factory CreateTaskDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'title': final String title}
        when title.isNotEmpty && title.length <= maxTitleLength =>
      CreateTaskDto(title),
    _ => throw const FormatException(
      '"title" must be a string of 1 to $maxTitleLength characters',
    ),
  };

  /// The longest accepted title.
  static const maxTitleLength = 200;

  /// What to do.
  final String title;
}
