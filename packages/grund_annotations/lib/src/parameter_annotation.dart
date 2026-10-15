/// Binds a route parameter to a part of the request.
///
/// A parameter without one of these annotations is a `HttpCtx` (passed as
/// is) or a value of the call scope, resolved by its type (and `Named`).
sealed class ParameterAnnotation {
  /// Creates the annotation.
  const ParameterAnnotation([this.name]);

  /// The name in the request; `null` means the name of the parameter.
  final String? name;
}

/// A path parameter (`:name` in the route path).
final class Path extends ParameterAnnotation {
  /// Creates the annotation.
  const Path({String? name}) : super(name);
}

/// A query parameter; a repeated one is a `List<String>`.
final class Query extends ParameterAnnotation {
  /// Creates the annotation.
  const Query({String? name}) : super(name);
}

/// A request header.
final class Header extends ParameterAnnotation {
  /// Creates the annotation.
  const Header({String? name}) : super(name);
}

/// A request cookie.
final class Cookie extends ParameterAnnotation {
  /// Creates the annotation.
  const Cookie({String? name}) : super(name);
}

/// The JSON request body: `T.fromJson(Map<String, Object?>)` (or a `List<T>`
/// of them), a `Map<String, Object?>`, or the raw bytes (`Uint8List`).
final class Body extends ParameterAnnotation {
  /// Creates the annotation.
  const Body();
}
