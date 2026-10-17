import '../errors/environment_errors.dart';

/// Environment variables read with checks: a variable that is set must be
/// valid, and only an unset one falls back.
final class Environment {
  /// Wraps the variables, usually `Platform.environment`; tests pass a map.
  /// The map is not copied.
  const Environment(this._values);

  static final RegExp _decimal = RegExp(r'^-?[0-9]+$');

  final Map<String, String> _values;

  /// Whether [name] is set; an empty value counts as set.
  bool has(String name) => _values.containsKey(name);

  /// The value of [name]; [fallback] when it is unset; throws
  /// [MissingVariableError] when it is unset and there is no [fallback].
  String string(String name, {String? fallback}) {
    if (_values[name] case final value?) return value;
    return fallback ?? (throw MissingVariableError(name));
  }

  /// The value of [name] as a decimal integer (`-?[0-9]+`) within [min] and
  /// [max]; [fallback] when it is unset.
  ///
  /// The [fallback] is written by the programmer and is not checked against
  /// [min] and [max]. Throws [MissingVariableError] or
  /// [InvalidVariableError].
  int integer(String name, {int? fallback, int? min, int? max}) {
    final text = _values[name];
    if (text == null) return fallback ?? (throw MissingVariableError(name));
    final value = _parse(text);
    if (value == null ||
        (min != null && value < min) ||
        (max != null && value > max)) {
      throw InvalidVariableError(name: name, expected: _expectation(min, max));
    }
    return value;
  }

  static int? _parse(String text) =>
      _decimal.hasMatch(text) ? int.tryParse(text) : null;

  static String _expectation(int? min, int? max) => switch ((min, max)) {
    (final low?, final high?) => 'an integer from $low to $high',
    (final low?, null) => 'an integer of at least $low',
    (null, final high?) => 'an integer of at most $high',
    (null, null) => 'an integer',
  };
}
