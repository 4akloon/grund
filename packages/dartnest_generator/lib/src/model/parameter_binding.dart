import 'body_kind.dart';

/// Where a handler parameter's value comes from.
sealed class ParameterBinding {
  /// Creates the binding.
  const ParameterBinding();
}

/// `@Param(name)`: a path parameter.
final class PathBinding extends ParameterBinding {
  /// Creates the binding.
  const PathBinding(this.name);

  /// The path parameter name.
  final String name;
}

/// `@Query(name)`: a query parameter.
final class QueryBinding extends ParameterBinding {
  /// Creates the binding.
  const QueryBinding(this.name);

  /// The query parameter name.
  final String name;
}

/// `@Header(name)`: a request header.
final class HeaderBinding extends ParameterBinding {
  /// Creates the binding.
  const HeaderBinding(this.name);

  /// The header name.
  final String name;
}

/// `@Body()`: the request body.
final class BodyBinding extends ParameterBinding {
  /// Creates the binding.
  const BodyBinding(this.kind);

  /// How the body is read.
  final BodyKind kind;
}

/// A parameter of type `ExecutionContext`.
final class ContextBinding extends ParameterBinding {
  /// Creates the binding.
  const ContextBinding();
}

/// A parameter of type `HttpRequest`.
final class RequestBinding extends ParameterBinding {
  /// Creates the binding.
  const RequestBinding();
}

/// A parameter that cannot be bound, because of [problem].
final class InvalidBinding extends ParameterBinding {
  /// Creates the binding.
  const InvalidBinding(this.problem);

  /// Why the parameter cannot be bound, as a sentence fragment.
  final String problem;
}
