/// Converters to JSON values for types that have no `toJson()`, such as
/// third-party classes.
///
/// ```dart
/// app.serializers.register<Money>((m) => {'amount': m.cents, 'cur': m.code});
/// ```
///
/// A converter applies to a handler result and to values nested in its
/// `Map`s and `List`s; it does not reach inside the output of another
/// object's `toJson()`. The first registered converter whose type matches
/// wins.
final class SerializerRegistry {
  /// Creates an empty registry.
  SerializerRegistry();

  final List<_Converter<Object>> _converters = [];

  /// Registers [toJson] for values of type [T].
  void register<T extends Object>(Object? Function(T value) toJson) {
    _converters.add(_Converter<T>(toJson));
  }

  /// Returns [value] with every registered type replaced by its JSON form,
  /// walking `Map` values and `List` elements; unchanged when nothing is
  /// registered.
  Object? prepare(Object? value) {
    if (_converters.isEmpty) return value;
    final converted = _convert(value);
    return switch (converted) {
      Map<Object?, Object?>() => {
        for (final MapEntry(:key, :value) in converted.entries)
          key: prepare(value),
      },
      List<Object?>() => [for (final item in converted) prepare(item)],
      _ => converted,
    };
  }

  Object? _convert(Object? value) {
    if (value == null) return null;
    for (final converter in _converters) {
      if (converter.accepts(value)) return converter.apply(value);
    }
    return value;
  }
}

final class _Converter<T extends Object> {
  _Converter(this._toJson);

  final Object? Function(T value) _toJson;

  bool accepts(Object value) => value is T;

  Object? apply(Object value) => _toJson(value as T);
}
