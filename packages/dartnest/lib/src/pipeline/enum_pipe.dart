import '../http/http_exception.dart';
import 'argument_meta.dart';
import 'pipe.dart';

/// Converts a string argument to the enum value with that name.
///
/// ```dart
/// final status = await context.query<Status>(
///   'status',
///   pipes: [EnumPipe(Status.values)],
/// );
/// ```
///
/// Non-string values (including `null` for an absent query parameter) pass
/// through unchanged.
final class EnumPipe<E extends Enum> implements Pipe<Object?, Object?> {
  /// Creates the pipe for [values] (usually `MyEnum.values`).
  const EnumPipe(this.values);

  /// The accepted values.
  final List<E> values;

  @override
  Object? transform(Object? value, ArgumentMeta meta) {
    if (value is! String) return value;
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw BadRequestException(
      message:
          'Invalid ${meta.source.label} "${meta.name}": expected one of '
          '${values.map((v) => v.name).join(', ')}, got "$value".',
    );
  }
}
