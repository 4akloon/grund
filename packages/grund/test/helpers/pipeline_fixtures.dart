// Recording pipeline components for ordering tests.
import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund/src/pipeline/endpoint.dart';
import 'package:grund/src/pipeline/resolved_enhancers.dart';

import 'http_fixtures.dart';

/// A guard that logs its [name] and answers [allow].
final class LogGuard implements Guard {
  LogGuard(this.log, this.name, {this.allow = true});
  final List<String> log;
  final String name;
  final bool allow;

  @override
  bool canActivate(ExecutionContext context) {
    log.add('guard $name');
    return allow;
  }
}

/// An interceptor that logs before and after the inner chain.
final class LogInterceptor implements Interceptor {
  LogInterceptor(this.log, this.name);
  final List<String> log;
  final String name;

  @override
  Future<Object?> intercept(
    ExecutionContext context,
    Next<Object?> next,
  ) async {
    log.add('before $name');
    final result = await next();
    log.add('after $name');
    return result;
  }
}

/// A filter for [E] that logs and answers `'<name> handled <error>'`.
final class LogFilter<E extends Object> extends ExceptionFilter<E> {
  LogFilter(this.log, this.name, {this.rethrowAs});
  final List<String> log;
  final String name;
  final Object? rethrowAs;

  @override
  Object? handle(E error, ExecutionContext context) {
    log.add('filter $name');
    final replacement = rethrowAs;
    if (replacement != null) throw replacement;
    return '$name handled $error';
  }
}

/// An endpoint whose handler logs `handler` and returns [handler]'s result.
Endpoint endpointWith(
  List<String> log, {
  ResolvedEnhancers enhancers = const ResolvedEnhancers(),
  FutureOr<Object?> Function()? handler,
}) => Endpoint(
  controllerType: Object,
  handlerName: 'test',
  metadata: const [],
  enhancers: enhancers,
  invoke: (context) {
    log.add('handler');
    return handler == null ? 'result' : handler();
  },
);

/// A context for `GET /`.
ExecutionContext plainContext() => contextFor(requestFor('GET', '/'));
