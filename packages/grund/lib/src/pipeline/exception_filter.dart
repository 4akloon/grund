import 'dart:async';

import 'execution_context.dart';
import 'pipeline_component.dart';

/// Turns an error of type [E] into a result.
///
/// A filter is a class to extend (not an interface) because [catches] needs
/// the type argument at runtime. The first filter whose [catches] accepts
/// the error handles it; route filters are tried before controller and
/// application filters. The returned value is serialized like a handler
/// result (return an `HttpResponse` to control the status). A filter may
/// throw: the new error goes to the filters after it, then to the default
/// filter.
///
/// ```dart
/// final class UserMissingFilter extends ExceptionFilter<UserMissing> {
///   const UserMissingFilter();
///   @override
///   Object? handle(UserMissing error, ExecutionContext context) =>
///       throw NotFoundException(message: 'No user ${error.id}');
/// }
/// ```
abstract class ExceptionFilter<E extends Object> implements PipelineComponent {
  /// Creates a filter.
  const ExceptionFilter();

  /// Whether this filter handles [error].
  bool catches(Object error) => error is E;

  /// Handles [error] for the request in [context].
  FutureOr<Object?> handle(E error, ExecutionContext context);
}
