import 'problem_error.dart';

/// A problem details object (RFC 9457), the body of every error response.
final class Problem {
  /// Creates the problem; [type] is `about:blank` when the status says it
  /// all.
  const Problem({
    this.type = 'about:blank',
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.code,
    this.errors = const [],
    this.extensions = const {},
  });

  /// URI that identifies the kind of problem.
  final String type;

  /// Short summary of the kind of problem (the reason phrase of [status]).
  final String title;

  /// The HTTP status of the response.
  final int status;

  /// What went wrong this time, for a person.
  final String? detail;

  /// URI that identifies this occurrence (the request path).
  final String? instance;

  /// Stable machine-readable identifier, an extension member.
  final String? code;

  /// The individual failures, an extension member.
  final List<ProblemError> errors;

  /// Further extension members; one never replaces a standard member.
  final Map<String, Object?> extensions;

  /// The problem as a JSON object: the standard members first, then the
  /// extensions.
  Map<String, Object?> toJson() => {
    'type': type,
    'title': title,
    'status': status,
    if (detail != null) 'detail': detail,
    if (instance != null) 'instance': instance,
    if (code != null) 'code': code,
    if (errors.isNotEmpty) 'errors': [for (final e in errors) e.toJson()],
    for (final MapEntry(:key, :value) in extensions.entries)
      if (!_standard.contains(key)) key: value,
  };

  static const _standard = {
    'type',
    'title',
    'status',
    'detail',
    'instance',
    'code',
    'errors',
  };
}
