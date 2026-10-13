import 'dart:async';

import '../http/http_exception.dart';
import 'endpoint.dart';
import 'exception_filter.dart';
import 'execution_context.dart';

/// Runs one request through guards → interceptors → handler → finish, and
/// sends any error to the exception filters. Transport-neutral: the
/// transport passes [run] a `finish` step that turns a result into its
/// response (HTTP serialization).
abstract final class Pipeline {
  /// Runs [endpoint] for [context].
  ///
  /// 1. Guards in order; the first `false` throws [ForbiddenException].
  /// 2. Interceptors as an onion around the handler.
  /// 3. `finish` on the result.
  ///
  /// An error from any step goes to the first filter that catches it; its
  /// result goes through `finish`. If a filter throws, the new error goes to
  /// the filters after it. An error no filter handles is rethrown with its
  /// original stack trace for the transport's default filter.
  static Future<R> run<R>(
    Endpoint endpoint,
    ExecutionContext context,
    FutureOr<R> Function(Object? result) finish,
  ) async {
    // Request boundary: every failure of user code, Errors included, must
    // reach the exception filters; nothing is swallowed (see CLAUDE.md).
    try {
      for (final guard in endpoint.enhancers.guards) {
        if (!await guard.canActivate(context)) {
          throw const ForbiddenException(message: 'Forbidden resource');
        }
      }
      return await finish(await _intercept(endpoint, context, 0));
    } on Object catch (error, stackTrace) {
      return _filter(endpoint.enhancers.filters, context, finish, (
        error,
        stackTrace,
      ));
    }
  }

  static Future<Object?> _intercept(
    Endpoint endpoint,
    ExecutionContext context,
    int index,
  ) async {
    final interceptors = endpoint.enhancers.interceptors;
    if (index == interceptors.length) return endpoint.invoke(context);
    return interceptors[index].intercept(
      context,
      () => _intercept(endpoint, context, index + 1),
    );
  }

  static Future<R> _filter<R>(
    List<ExceptionFilter<Object>> filters,
    ExecutionContext context,
    FutureOr<R> Function(Object? result) finish,
    (Object, StackTrace) failure,
  ) async {
    var (error, stackTrace) = failure;
    for (final filter in filters) {
      // Same boundary as in [run]: a filter that throws, in `catches` or in
      // `handle`, hands its error to the filters after it.
      try {
        if (!filter.catches(error)) continue;
        return await finish(await filter.handle(error, context));
      } on Object catch (next, nextStackTrace) {
        (error, stackTrace) = (next, nextStackTrace);
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}
