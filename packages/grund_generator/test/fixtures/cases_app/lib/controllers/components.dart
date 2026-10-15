// Pipeline components and metadata shared by the controller scenarios.
import 'dart:async';

import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

/// Roles allowed to call a handler.
final class Roles extends RouteMetadata {
  /// Creates the metadata.
  const Roles(this.names);

  /// The role names.
  final List<String> names;
}

/// Lets every request through.
final class OpenGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

/// Passes the result through.
final class PassInterceptor implements Interceptor {
  @override
  FutureOr<Object?> intercept(ExecutionContext context, Next<Object?> next) =>
      next();
}

/// Trims strings.
final class TrimPipe implements Pipe<Object?, Object?> {
  @override
  Object? transform(Object? value, ArgumentMeta meta) =>
      value is String ? value.trim() : value;
}

/// Maps [StateError] to 404.
final class StateFilter extends ExceptionFilter<StateError> {
  @override
  Object? handle(StateError error, ExecutionContext context) =>
      throw const NotFoundException(message: 'Gone');
}
