import 'dart:async';

import 'enhancers.dart';
import 'execution_context.dart';

/// What the pipeline needs to know about one handler, independent of the
/// transport: its name, its own pipeline components and metadata, and how
/// to invoke it.
///
/// HTTP `Route` extends it; GraphQL fields will too, so both share the
/// guards → interceptors → handler → filters pipeline.
abstract base class HandlerSpec {
  /// Creates the description.
  HandlerSpec({
    required this.name,
    this.enhancers = Enhancers.none,
    this.metadata = const [],
  });

  /// Handler name, reported as `ExecutionContext.handlerName`.
  final String name;

  /// Pipeline components of this handler (innermost level).
  final Enhancers enhancers;

  /// Metadata of this handler; overrides the controller's.
  final List<Object> metadata;

  /// Invokes the handler on [target] (the controller instance).
  FutureOr<Object?> invoke(Object target, ExecutionContext context);
}
