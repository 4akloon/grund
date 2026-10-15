import 'serializer_registry.dart';

/// Turns values of a type without `toJson()` into JSON for the response.
///
/// ```dart
/// HttpModule(codecs: [
///   ResponseCodec<Money>((m) => {'amount': m.cents, 'currency': m.code}),
/// ])
/// ```
///
/// Write the type argument: the codec applies to values of exactly that
/// type (and its subtypes).
final class ResponseCodec<T extends Object> {
  /// Creates the codec from [toJson].
  const ResponseCodec(this.toJson);

  /// Converts a value to a JSON value (`Map`, `List`, `String`, `num`,
  /// `bool` or `null`).
  final Object? Function(T value) toJson;

  /// Adds this codec to [registry] under its type [T].
  void registerIn(SerializerRegistry registry) => registry.register<T>(toJson);
}
