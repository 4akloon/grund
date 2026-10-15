import 'dart:async';

import 'execution_context.dart';
import 'pipeline_component.dart';

/// Continues to the next step of a chain and completes with its result.
typedef Next<T> = Future<T> Function();

/// Wraps the handler: runs code before and after it, replaces its result,
/// or answers without calling it.
///
/// ```dart
/// final class TimingInterceptor implements Interceptor {
///   @override
///   Future<Object?> intercept(ExecutionContext context, Next<Object?> next) async {
///     final watch = Stopwatch()..start();
///     final result = await next();
///     context.switchToHttp().response.headers.set('x-ms', '${watch.elapsedMilliseconds}');
///     return result;
///   }
/// }
/// ```
abstract interface class Interceptor implements PipelineComponent {
  /// Handles [context]; call [next] at most once to run the inner chain.
  FutureOr<Object?> intercept(ExecutionContext context, Next<Object?> next);
}
