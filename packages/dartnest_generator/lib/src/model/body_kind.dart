/// How a `@Body()` parameter is read.
enum BodyKind {
  /// `T.fromJson(json)`.
  fromJson,

  /// The decoded JSON object as a `Map<String, Object?>`.
  jsonObject,

  /// The body as text.
  text,

  /// The body as bytes.
  bytes,

  /// No way to read the type: it has no `fromJson`.
  unsupported,
}
