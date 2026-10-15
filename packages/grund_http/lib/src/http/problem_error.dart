/// One failure inside a [Problem]: a rejected field, parameter or header.
final class ProblemError {
  /// Creates the entry.
  const ProblemError({required this.detail, this.pointer, this.code});

  /// What is wrong, for a person.
  final String detail;

  /// JSON pointer to the offending input (`/body/title`, `/query/page`).
  final String? pointer;

  /// Stable machine-readable identifier of this failure.
  final String? code;

  /// The entry as a JSON object; absent members are left out.
  Map<String, Object?> toJson() => {
    'detail': detail,
    if (pointer != null) 'pointer': pointer,
    if (code != null) 'code': code,
  };
}
