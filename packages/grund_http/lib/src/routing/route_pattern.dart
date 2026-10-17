import 'pattern_segment.dart';
import 'routing_error.dart';

/// A parsed route path: static segments, `:name` parameters and an optional
/// trailing `*` wildcard.
///
/// Empty segments are dropped, so `/users/`, `users` and `//users` are the
/// same pattern `/users`. A parameter or wildcard must be a whole segment; a
/// parameter may end with a literal suffix (`:slug.md`).
final class RoutePattern {
  RoutePattern._(this.segments);

  /// The segments in order.
  final List<PatternSegment> segments;

  static final _parameter = RegExp(
    r'^([A-Za-z_][A-Za-z0-9_]*)((?:\.[A-Za-z0-9_~-]+)*)$',
  );

  /// Parses [path] relative to the controller [prefix]; throws
  /// [InvalidRoutePatternError].
  static RoutePattern join(String prefix, String path) {
    final parts = '$prefix/$path'
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final display = '/${parts.join('/')}';
    final segments = <PatternSegment>[
      for (var i = 0; i < parts.length; i++)
        _segment(parts[i], isLast: i == parts.length - 1, pattern: display),
    ];
    _checkUniqueNames(segments, display);
    return RoutePattern._(List.unmodifiable(segments));
  }

  /// Parameter names in order; the wildcard contributes `*`.
  List<String> get parameterNames => [
    for (final segment in segments)
      if (segment case ParamSegment(:final name))
        name
      else if (segment is WildcardSegment)
        WildcardSegment.parameterName,
  ];

  static PatternSegment _segment(
    String part, {
    required bool isLast,
    required String pattern,
  }) {
    if (part == '*') {
      if (isLast) return const WildcardSegment();
      _fail(pattern, 'the wildcard "*" must be the last segment');
    }
    if (part.startsWith(':')) {
      final name = part.substring(1);
      if (_parameter.firstMatch(name) case final match?) {
        return ParamSegment(match[1]!, suffix: match[2]!);
      }
      _fail(
        pattern,
        'parameter name "$name" must match [A-Za-z_][A-Za-z0-9_]*, '
        'optionally followed by a literal suffix such as ".md"',
      );
    }
    if (part.contains(':') || part.contains('*')) {
      _fail(
        pattern,
        'segment "$part" mixes literal text with ":" or "*"; parameters and '
        'wildcards must be whole segments',
      );
    }
    return StaticSegment(part);
  }

  static void _checkUniqueNames(List<PatternSegment> segments, String pattern) {
    final seen = <String>{};
    for (final segment in segments) {
      if (segment is ParamSegment && !seen.add(segment.name)) {
        _fail(pattern, 'parameter ":${segment.name}" appears twice');
      }
    }
  }

  static Never _fail(String pattern, String reason) =>
      throw InvalidRoutePatternError(pattern: pattern, reason: reason);

  @override
  String toString() => '/${segments.join('/')}';
}
