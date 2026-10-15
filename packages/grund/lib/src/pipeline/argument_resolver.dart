import 'dart:async';

import '../http/http_exception.dart';
import 'argument_meta.dart';
import 'pipe.dart';
import 'pipeline_error.dart';
import 'value_converter.dart';

/// Runs pipes over a raw argument and converts the result to the requested
/// type.
abstract final class ArgumentResolver {
  /// Pipes [raw] through [pipes] in order, then: a value that already is a
  /// [T] is returned; `null` for a non-nullable [T] throws
  /// [BadRequestException] (missing argument); a `String` goes through
  /// [ValueConverter]; anything else throws [UnsupportedConversionError].
  static Future<T> resolve<T>(
    Object? raw,
    ArgumentMeta meta,
    List<Pipe<Object?, Object?>> pipes,
  ) async {
    final value = await pipe(raw, meta, pipes);
    if (value is T) return value;
    if (value == null) {
      throw BadRequestException(
        message: 'Missing ${meta.source.label} "${meta.name}".',
      );
    }
    if (value is String) return ValueConverter.convert<T>(value, meta);
    throw UnsupportedConversionError(
      argument: meta,
      valueType: value.runtimeType,
    );
  }

  /// Pipes [raw] through [pipes] in order.
  static Future<Object?> pipe(
    Object? raw,
    ArgumentMeta meta,
    List<Pipe<Object?, Object?>> pipes,
  ) async {
    var value = raw;
    for (final pipe in pipes) {
      value = await pipe.transform(value, meta);
    }
    return value;
  }
}
