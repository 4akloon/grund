import 'dart:async';

import 'execution_context.dart';
import 'pipeline_component.dart';

/// Decides whether a request may reach its handler.
///
/// Returning `false` produces 403 (`ForbiddenException`); throwing an
/// `HttpException` (for example `UnauthorizedException`) produces that
/// status instead.
abstract interface class Guard implements PipelineComponent {
  /// Whether the handler may run for [context].
  FutureOr<bool> canActivate(ExecutionContext context);
}
