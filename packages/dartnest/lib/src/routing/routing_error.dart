import '../di/errors.dart';

/// Errors in the declared routes, raised by `Application.create` before any
/// provider is created.
sealed class RoutingError extends DartnestError {
  /// Creates a routing error.
  const RoutingError();
}

/// Two handlers are declared for the same method and path.
final class DuplicateRouteError extends RoutingError {
  /// Creates the error.
  const DuplicateRouteError({
    required this.method,
    required this.path,
    required this.existing,
    required this.duplicate,
  });

  /// The upper-cased method.
  final String method;

  /// The normalized path pattern, for example `/users/:id`.
  final String path;

  /// The handler declared first, as `Controller.handler (module "id")`.
  final String existing;

  /// The handler declared second, in the same format.
  final String duplicate;

  @override
  String get message =>
      'Route $method $path is declared twice: by $existing and by $duplicate. '
      'Parameter names do not distinguish routes.';
}

/// A route path cannot be parsed.
final class InvalidRoutePatternError extends RoutingError {
  /// Creates the error.
  const InvalidRoutePatternError({required this.pattern, required this.reason});

  /// The normalized pattern (controller path joined with the route path).
  final String pattern;

  /// What is wrong with it.
  final String reason;

  @override
  String get message => 'Invalid route pattern "$pattern": $reason.';
}
