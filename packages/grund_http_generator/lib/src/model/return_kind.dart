/// What a route handler returns, which decides how the generated handler
/// ends.
enum ReturnKind {
  /// A value (or a `Future` of one): serialized by the response codec.
  value,

  /// `void`, `Null` or a `Future` of them: the handler returns `null`, a 204.
  none,

  /// `Stream<List<int>>`: streamed bytes.
  byteStream,

  /// Any other `Stream<T>`: reserved for the SSE package.
  stream,

  /// A function, record or type parameter: cannot be a response.
  unsupported,
}
