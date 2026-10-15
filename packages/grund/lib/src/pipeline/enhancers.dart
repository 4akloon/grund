import 'pipeline_component.dart';

/// Guards, interceptors, pipes and exception filters attached to an
/// application, a controller or a route.
///
/// Each entry is a ready instance or a [Use] reference resolved from DI.
/// Levels compose as follows: guards, interceptors and pipes run
/// application → controller → route (interceptors wrap like an onion, the
/// application's outermost); exception filters are tried route → controller
/// → application, then the default filter.
///
/// ```dart
/// const Enhancers(guards: [Use<AuthGuard>()], filters: [DbErrorFilter()]);
/// ```
final class Enhancers {
  /// Creates the lists; every list defaults to empty.
  const Enhancers({
    this.guards = const [],
    this.interceptors = const [],
    this.pipes = const [],
    this.filters = const [],
  });

  /// No components.
  static const none = Enhancers();

  /// `Guard`s or `Use` references to them.
  final List<PipelineComponent> guards;

  /// `Interceptor`s or `Use` references to them.
  final List<PipelineComponent> interceptors;

  /// `Pipe`s or `Use` references to them.
  final List<PipelineComponent> pipes;

  /// `ExceptionFilter`s or `Use` references to them.
  final List<PipelineComponent> filters;
}
