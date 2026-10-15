import '../http/http_exception.dart';
import 'argument_meta.dart';
import 'pipeline_error.dart';

/// Built-in conversion of a raw string argument to `int`, `double`, `num`,
/// `bool` (`true`/`false`) or `DateTime` (ISO 8601), nullable or not.
abstract final class ValueConverter {
  /// Converts [raw] to [T]; an unparsable value throws
  /// [BadRequestException], an unsupported [T] throws
  /// [UnsupportedConversionError].
  static T convert<T>(String raw, ArgumentMeta meta) {
    final Object? parsed;
    if (_targets<T, int>()) {
      parsed = int.tryParse(raw);
    } else if (_targets<T, double>()) {
      parsed = double.tryParse(raw);
    } else if (_targets<T, num>()) {
      parsed = num.tryParse(raw);
    } else if (_targets<T, bool>()) {
      parsed = switch (raw) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    } else if (_targets<T, DateTime>()) {
      parsed = DateTime.tryParse(raw);
    } else {
      throw UnsupportedConversionError(argument: meta, valueType: String);
    }
    if (parsed is T && parsed != null) return parsed;
    throw BadRequestException(
      message:
          'Invalid ${meta.source.label} "${meta.name}": expected '
          '${_typeOf<T>()}, got "$raw".',
    );
  }

  /// Whether [T] is [S] or `S?`.
  static bool _targets<T, S>() => T == S || T == _typeOf<S?>();

  static Type _typeOf<X>() => X;
}
