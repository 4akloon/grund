import '../http/http_exception.dart';
import '../http/problem_code.dart';
import 'param_location.dart';

/// The checks a parameter reader applies to a value it has parsed, and the
/// errors it reports: always a [BadRequestException] with a stable `code` and
/// the pointer `/<location>/<name>`.
abstract final class ParamConstraints {
  static const _shownLength = 64;

  /// The error for a parameter that is absent.
  static BadRequestException missing(ParamLocation location, String name) =>
      BadRequestException(
        message: 'Missing ${location.label} "$name".',
        code: ProblemCode.parameterMissing,
        pointer: _pointer(location, name),
      );

  /// The error for a value that is not a [expected].
  static BadRequestException invalid(
    ParamLocation location,
    String name,
    String raw,
    String expected,
  ) => BadRequestException(
    message:
        'Invalid ${location.label} "$name": expected $expected, '
        'got "${_shown(raw)}".',
    code: ProblemCode.parameterInvalid,
    pointer: _pointer(location, name),
  );

  /// The error for a value outside the allowed range.
  static BadRequestException outOfRange(
    ParamLocation location,
    String name,
    String requirement,
  ) => BadRequestException(
    message: 'The ${location.label} "$name" must be $requirement.',
    code: ProblemCode.parameterOutOfRange,
    pointer: _pointer(location, name),
  );

  /// Checks [value] against the inclusive bounds [min] and [max].
  static void checkRange(
    ParamLocation location,
    String name,
    num value, {
    num? min,
    num? max,
  }) {
    if (min != null && value < min) {
      throw outOfRange(location, name, 'at least $min');
    }
    if (max != null && value > max) {
      throw outOfRange(location, name, 'at most $max');
    }
  }

  /// Checks the length of [value] against [minLength] and [maxLength].
  static void checkLength(
    ParamLocation location,
    String name,
    String value, {
    int? minLength,
    int? maxLength,
  }) {
    if (minLength != null && value.length < minLength) {
      throw outOfRange(location, name, 'at least $minLength characters long');
    }
    if (maxLength != null && value.length > maxLength) {
      throw outOfRange(location, name, 'at most $maxLength characters long');
    }
  }

  /// Checks that [value] matches [pattern] as a whole.
  ///
  /// A [pattern] that is not a valid regular expression is a bug of the
  /// developer, not of the client: it throws a [FormatException] when used.
  static void checkPattern(
    ParamLocation location,
    String name,
    String value,
    String pattern,
  ) {
    if (RegExp('^(?:$pattern)\$').hasMatch(value)) return;
    throw invalid(location, name, value, 'a value matching /$pattern/');
  }

  /// Checks that [value] is one of [allowed].
  static void checkOneOf(
    ParamLocation location,
    String name,
    String value,
    List<String> allowed,
  ) {
    if (allowed.contains(value)) return;
    throw invalid(location, name, value, 'one of ${allowed.join(', ')}');
  }

  static String _pointer(ParamLocation location, String name) =>
      '/${location.pointerSegment}/$name';

  static String _shown(String raw) =>
      raw.length <= _shownLength ? raw : '${raw.substring(0, _shownLength)}...';
}
