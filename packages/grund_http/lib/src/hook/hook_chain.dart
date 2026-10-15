import 'dart:async';

import 'package:grund/grund.dart';
import 'package:logging/logging.dart';

import '../ctx/http_ctx.dart';
import '../http/http_response.dart';
import 'hook_ref.dart';
import 'http_hook.dart';

/// The hooks that wrap one request, outermost first: the global ones, then
/// those of the API, then those of the route.
///
/// `before` hooks run outer to inner, `after` and `onError` inner to outer.
/// A failure in any `before` ends the chain: no later `before`, no handler
/// and no `after` runs; the error goes to the `onError` of the hooks.
final class HookChain {
  /// Creates the chain over resolved [hooks], outermost first.
  const HookChain(this.hooks);

  /// Resolves [refs] (outermost first) through [injector].
  ///
  /// Throws `MissingProviderError` for a hook type nobody provides.
  factory HookChain.resolve(
    Iterable<HookRef<HttpHook>> refs,
    Injector injector,
  ) => HookChain([for (final ref in refs) ref.resolve(injector)]);

  static final Logger _logger = Logger('grund.http');

  /// The hooks, outermost first.
  final List<HttpHook> hooks;

  /// Runs the `before` hooks, [handler] and the `after` hooks, and returns
  /// the handler's result.
  ///
  /// When anything throws, the `onError` hooks are asked in reverse order;
  /// the first non-null response is returned instead of the result. An error
  /// that an `onError` throws is what the next hook is offered (and the
  /// replaced error is logged as `FINE` on `grund.http`). When nobody
  /// answers, the last error is rethrown with its stack trace.
  Future<Object?> run(
    HttpCtx c,
    FutureOr<Object?> Function(HttpCtx c) handler,
  ) async {
    // Hook chain boundary: hooks and the handler are user code; every
    // failure is offered to onError and, unanswered, rethrown unchanged.
    try {
      for (final hook in hooks) {
        await hook.before(c);
      }
      final result = await handler(c);
      for (final hook in hooks.reversed) {
        await hook.after(c, result);
      }
      return result;
    } on Object catch (error, stackTrace) {
      return _recover(c, error, stackTrace);
    }
  }

  Future<HttpResponse> _recover(
    HttpCtx c,
    Object error,
    StackTrace stackTrace,
  ) async {
    var failure = (error, stackTrace);
    for (final hook in hooks.reversed) {
      // Hook chain boundary: a throwing onError replaces the error the
      // remaining hooks are offered.
      try {
        final response = await hook.onError(c, failure.$1, failure.$2);
        if (response != null) return response;
      } on Object catch (thrown, thrownTrace) {
        _logger.fine(
          '${hook.runtimeType}.onError replaced ${failure.$1.runtimeType} '
          'with ${thrown.runtimeType}',
          failure.$1,
          failure.$2,
        );
        failure = (thrown, thrownTrace);
      }
    }
    Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}
