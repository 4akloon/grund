/// Binds a handler parameter to a part of the request.
///
/// A parameter without one of these annotations must have the type
/// `ExecutionContext` or `HttpRequest`.
sealed class ArgumentAnnotation {
  /// Creates the annotation.
  const ArgumentAnnotation();
}

/// The path parameter [name] (`:name` in the route path), converted to the
/// parameter type like `ExecutionContext.param`.
final class Param extends ArgumentAnnotation {
  /// Creates the annotation.
  const Param(this.name);

  /// The path parameter name, without the colon.
  final String name;
}

/// The query parameter [name], converted like `ExecutionContext.query`; a
/// nullable parameter type makes it optional.
final class Query extends ArgumentAnnotation {
  /// Creates the annotation.
  const Query(this.name);

  /// The query parameter name.
  final String name;
}

/// The request header [name]; the parameter type is `String` (a missing
/// header is a 400) or `String?`.
final class Header extends ArgumentAnnotation {
  /// Creates the annotation.
  const Header(this.name);

  /// The header name (case-insensitive).
  final String name;
}

/// The request body: `T.fromJson` when the type has a `fromJson` factory or
/// static method taking a JSON map, otherwise a `Map<String, Object?>`,
/// `String` or `List<int>` directly.
final class Body extends ArgumentAnnotation {
  /// Creates the annotation.
  const Body();
}
