/// The stable `code` values and pointers the framework puts into problems.
abstract final class ProblemCode {
  /// The request body is not UTF-8, not JSON, not an object or not what the
  /// body reader expected.
  static const bodyInvalid = 'body_invalid';

  /// The request body is larger than `HttpConfig.maxBodyBytes`.
  static const bodyTooLarge = 'body_too_large';

  /// A required path, query, header or cookie value is absent.
  static const parameterMissing = 'parameter_missing';

  /// A parameter value cannot be read as the requested type or violates a
  /// pattern or an enumeration.
  static const parameterInvalid = 'parameter_invalid';

  /// A number or a length is outside the allowed range.
  static const parameterOutOfRange = 'parameter_out_of_range';

  /// No route matches the path.
  static const routeNotFound = 'route_not_found';

  /// A route matches the path, but not the method.
  static const methodNotAllowed = 'method_not_allowed';

  /// The server is shutting down.
  static const serverUnavailable = 'server_unavailable';

  /// The JSON pointer of the request body.
  static const bodyPointer = '/body';
}
