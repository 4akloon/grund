import 'package:grund/grund.dart' show GrundError;

/// A handler result cannot be encoded as JSON.
final class SerializationError extends GrundError {
  /// Creates the error.
  const SerializationError({required this.valueType, this.cause});

  /// Runtime type of the value that could not be encoded.
  final Type valueType;

  /// What the JSON encoder reported, if anything.
  final Object? cause;

  @override
  String get message {
    final failure = cause;
    // The encoder reports a value without toJson() as a NoSuchMethodError
    // cause; any other cause is a toJson() that threw.
    if (failure != null && failure is! NoSuchMethodError) {
      return 'Cannot serialize $valueType to JSON: its toJson() or the JSON '
          'encoder failed with $failure. Codecs do not apply to '
          'values inside the result of a toJson().';
    }
    return 'Cannot serialize $valueType to JSON. Give it a toJson() method, '
        'return an HttpResponse, or add a '
        'ResponseCodec<$valueType>(...) to HttpModule(codecs: ...). Codecs '
        'do not apply to values inside the result of a toJson().';
  }
}
