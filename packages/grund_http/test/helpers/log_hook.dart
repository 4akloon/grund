import 'dart:async';

import 'package:grund_http/grund_http.dart';

/// A hook that writes what it sees to [log] and fails where it is told to.
final class LogHook extends HttpHook {
  LogHook(
    this.name,
    this.log, {
    this.failBefore,
    this.failAfter,
    this.answers,
    this.failOnError,
  });

  final String name;
  final List<String> log;

  /// Thrown by `before` when set.
  final Object? failBefore;

  /// Thrown by `after` when set.
  final Object? failAfter;

  /// Returned by `onError` when set.
  final HttpResponse? answers;

  /// Thrown by `onError` when set.
  final Object? failOnError;

  @override
  FutureOr<void> before(HttpCtx c) {
    log.add('before $name');
    if (failBefore case final error?) throw error;
  }

  @override
  FutureOr<void> after(HttpCtx c, Object? result) {
    log.add('after $name $result');
    if (failAfter case final error?) throw error;
  }

  @override
  FutureOr<HttpResponse?> onError(HttpCtx c, Object error, StackTrace stack) {
    log.add('onError $name ${error.runtimeType}');
    if (failOnError case final failure?) throw failure;
    return answers;
  }
}
