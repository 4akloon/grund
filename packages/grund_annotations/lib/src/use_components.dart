/// Attaches pipeline components to a controller or a route; each type is
/// resolved through dependency injection (`Use<T>()` in the explicit API),
/// so it must be a provider visible in the controller's module.
sealed class UseComponents {
  /// Creates the annotation for [types].
  const UseComponents(this.types);

  /// The component classes, in order.
  final List<Type> types;
}

/// Guards; each type implements `Guard`.
final class UseGuards extends UseComponents {
  /// Creates the annotation.
  const UseGuards(super.types);
}

/// Interceptors; each type implements `Interceptor`.
final class UseInterceptors extends UseComponents {
  /// Creates the annotation.
  const UseInterceptors(super.types);
}

/// Pipes; each type implements `Pipe`.
final class UsePipes extends UseComponents {
  /// Creates the annotation.
  const UsePipes(super.types);
}

/// Exception filters; each type extends `ExceptionFilter`.
final class UseFilters extends UseComponents {
  /// Creates the annotation.
  const UseFilters(super.types);
}
