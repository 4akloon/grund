import 'dart:async';

import 'execution_context.dart';
import 'resolved_enhancers.dart';

/// A handler ready to run: bound to its controller instance, with the
/// application, controller and route components resolved and combined.
final class Endpoint {
  /// Creates the endpoint.
  const Endpoint({
    required this.controllerType,
    required this.handlerName,
    required this.metadata,
    required this.enhancers,
    required this.invoke,
  });

  /// The controller class.
  final Type controllerType;

  /// The handler name.
  final String handlerName;

  /// Route metadata followed by controller metadata.
  final List<Object> metadata;

  /// The combined pipeline components.
  final ResolvedEnhancers enhancers;

  /// Calls the handler on the bound controller instance.
  final FutureOr<Object?> Function(ExecutionContext context) invoke;
}
