import 'application_error.dart';
import '../di/injector.dart';
import 'enhancers.dart';
import 'exception_filter.dart';
import 'guard.dart';
import 'interceptor.dart';
import 'pipe.dart';
import 'pipeline_component.dart';
import 'use.dart';

/// [Enhancers] with every `Use` resolved and every entry type-checked.
final class ResolvedEnhancers {
  /// Creates the lists.
  const ResolvedEnhancers({
    this.guards = const [],
    this.interceptors = const [],
    this.pipes = const [],
    this.filters = const [],
  });

  /// Guards in execution order.
  final List<Guard> guards;

  /// Interceptors, outermost first.
  final List<Interceptor> interceptors;

  /// Pipes in execution order.
  final List<Pipe<Object?, Object?>> pipes;

  /// Exception filters in the order they are tried.
  final List<ExceptionFilter<Object>> filters;

  /// Resolves [enhancers] through [injector]; [owner] names the declaring
  /// application, controller or route in [InvalidComponentError].
  static ResolvedEnhancers resolve(
    Enhancers enhancers,
    Injector injector, {
    required String owner,
  }) {
    List<C> all<C extends PipelineComponent>(
      List<PipelineComponent> components,
      String slot,
    ) => [
      for (final component in components)
        _resolveOne<C>(component, injector, owner: owner, slot: slot),
    ];
    return ResolvedEnhancers(
      guards: all<Guard>(enhancers.guards, 'guards'),
      interceptors: all<Interceptor>(enhancers.interceptors, 'interceptors'),
      pipes: all<Pipe<Object?, Object?>>(enhancers.pipes, 'pipes'),
      filters: all<ExceptionFilter<Object>>(enhancers.filters, 'filters'),
    );
  }

  /// Combines levels given outermost first (application, controller,
  /// route): guards, interceptors and pipes keep that order; filters are
  /// reversed so the innermost level is tried first.
  static ResolvedEnhancers chain(List<ResolvedEnhancers> outerToInner) =>
      ResolvedEnhancers(
        guards: [for (final level in outerToInner) ...level.guards],
        interceptors: [for (final level in outerToInner) ...level.interceptors],
        pipes: [for (final level in outerToInner) ...level.pipes],
        filters: [for (final level in outerToInner.reversed) ...level.filters],
      );

  static C _resolveOne<C extends PipelineComponent>(
    PipelineComponent component,
    Injector injector, {
    required String owner,
    required String slot,
  }) {
    final resolved = switch (component) {
      Use() => component.resolve(injector),
      _ => component,
    };
    if (resolved is C) return resolved;
    throw InvalidComponentError(
      owner: owner,
      slot: slot,
      actualType: resolved.runtimeType,
      expectedType: C,
    );
  }
}
