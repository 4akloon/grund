/// How a `@Body()` parameter is read.
enum BodyKind {
  /// `await c.body(T.fromJson)`.
  object,

  /// `await c.bodyList(T.fromJson)` for a `List<T>`.
  list,

  /// The decoded JSON object as a `Map<String, Object?>`.
  jsonObject,

  /// The raw bytes as a `Uint8List`.
  bytes,

  /// No way to read the type: no `fromJson`, or nullable.
  unsupported,
}
