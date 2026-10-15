import 'param_constraints.dart';
import 'param_location.dart';

/// Typed readers for the parameters of one [ParamLocation] of a request.
///
/// All validation happens in the readers: an absent required parameter, a
/// value of the wrong type, or one outside the given constraints throws a
/// `BadRequestException` (400) with a stable `code` (`parameter_missing`,
/// `parameter_invalid`, `parameter_out_of_range`) and the pointer
/// `/<location>/<name>`. The `...OrNull` readers return `null` for an absent
/// parameter and still reject an invalid one. A repeated parameter reads as
/// its first value; [all] returns every value.
final class Params {
  /// Creates readers over [lookup], which returns every value of a name
  /// (empty when absent).
  Params(this.location, this._lookup);

  /// Where the values come from.
  final ParamLocation location;

  final List<String> Function(String name) _lookup;

  /// Every value of [name], in order; empty when absent.
  List<String> all(String name) => _lookup(name);

  /// The text of [name], optionally constrained by length, a full-match
  /// [pattern] or a list of allowed values.
  String string(
    String name, {
    int? minLength,
    int? maxLength,
    String? pattern,
    List<String>? oneOf,
  }) => _required(
    name,
    stringOrNull(
      name,
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
      oneOf: oneOf,
    ),
  );

  /// Like [string], `null` when absent.
  String? stringOrNull(
    String name, {
    int? minLength,
    int? maxLength,
    String? pattern,
    List<String>? oneOf,
  }) {
    final raw = _first(name);
    if (raw == null) return null;
    ParamConstraints.checkLength(
      location,
      name,
      raw,
      minLength: minLength,
      maxLength: maxLength,
    );
    if (pattern != null) {
      ParamConstraints.checkPattern(location, name, raw, pattern);
    }
    if (oneOf != null) ParamConstraints.checkOneOf(location, name, raw, oneOf);
    return raw;
  }

  /// The decimal integer in [name], within the inclusive [min] and [max].
  int integer(String name, {int? min, int? max}) =>
      _required(name, integerOrNull(name, min: min, max: max));

  /// Like [integer], `null` when absent.
  int? integerOrNull(String name, {int? min, int? max}) {
    final raw = _first(name);
    if (raw == null) return null;
    final value = _integerPattern.hasMatch(raw) ? int.tryParse(raw) : null;
    if (value == null) _fail(name, raw, 'an integer');
    ParamConstraints.checkRange(location, name, value, min: min, max: max);
    return value;
  }

  /// The finite number in [name], within the inclusive [min] and [max].
  double decimal(String name, {double? min, double? max}) =>
      _required(name, decimalOrNull(name, min: min, max: max));

  /// Like [decimal], `null` when absent.
  double? decimalOrNull(String name, {double? min, double? max}) {
    final raw = _first(name);
    if (raw == null) return null;
    final value = raw == raw.trim() ? double.tryParse(raw) : null;
    if (value == null || !value.isFinite) _fail(name, raw, 'a number');
    ParamConstraints.checkRange(location, name, value, min: min, max: max);
    return value;
  }

  /// The literal `true` or `false` in [name].
  bool boolean(String name) => _required(name, booleanOrNull(name));

  /// Like [boolean], `null` when absent.
  bool? booleanOrNull(String name) {
    final raw = _first(name);
    if (raw == null) return null;
    return switch (raw) {
      'true' => true,
      'false' => false,
      _ => _fail(name, raw, 'true or false'),
    };
  }

  /// The ISO 8601 date and time in [name].
  DateTime dateTime(String name) => _required(name, dateTimeOrNull(name));

  /// Like [dateTime], `null` when absent.
  DateTime? dateTimeOrNull(String name) {
    final raw = _first(name);
    if (raw == null) return null;
    return DateTime.tryParse(raw) ?? _fail(name, raw, 'an ISO 8601 date-time');
  }

  /// The URI in [name].
  Uri uri(String name) => _required(name, uriOrNull(name));

  /// Like [uri], `null` when absent.
  Uri? uriOrNull(String name) {
    final raw = _first(name);
    if (raw == null) return null;
    final value = raw.isEmpty ? null : Uri.tryParse(raw);
    return value ?? _fail(name, raw, 'a URI');
  }

  /// The element of [values] whose `name` equals the text in [name].
  E enumOf<E extends Enum>(String name, List<E> values) =>
      _required(name, enumOfOrNull(name, values));

  /// Like [enumOf], `null` when absent.
  E? enumOfOrNull<E extends Enum>(String name, List<E> values) {
    final raw = _first(name);
    if (raw == null) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return _fail(name, raw, 'one of ${values.map((v) => v.name).join(', ')}');
  }

  static final _integerPattern = RegExp(r'^[+-]?\d+$');

  String? _first(String name) {
    final values = _lookup(name);
    return values.isEmpty ? null : values.first;
  }

  T _required<T extends Object>(String name, T? value) =>
      value ?? (throw ParamConstraints.missing(location, name));

  Never _fail(String name, String raw, String expected) =>
      throw ParamConstraints.invalid(location, name, raw, expected);
}
