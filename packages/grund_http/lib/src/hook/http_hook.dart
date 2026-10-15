import 'dart:async';

import '../ctx/http_ctx.dart';
import '../http/http_response.dart';

/// Code that runs around a route handler: authentication, authorization,
/// validation, auditing, error translation.
///
/// One hook replaces the guards, interceptors, pipes and exception filters of
/// other frameworks. All three methods are optional.
///
/// - [before] runs before the handler. Throw an `HttpException` to refuse the
///   request; hand a value to the handler with `c.set<T>(value)`.
/// - [after] runs after the handler returned, with its result.
/// - [onError] runs when anything in the chain failed and may answer instead.
///
/// A hook is referenced by a `HookRef`: by type (resolved from the module
/// graph, so it may depend on services) or as a constant instance (when it is
/// parameterized, `RolesHook(Role.editor)`; it reads services with `c<T>()`).
abstract class HttpHook {
  /// Creates the hook; subclasses with only final fields can be `const`.
  const HttpHook();

  /// Runs before the handler; a thrown error ends the chain.
  FutureOr<void> before(HttpCtx c) {}

  /// Runs after the handler succeeded, with the value it returned.
  FutureOr<void> after(HttpCtx c, Object? result) {}

  /// Offered the [error] of the chain; a non-null response replaces it.
  ///
  /// Every hook of the chain is asked, innermost first, also one whose
  /// [before] did not run because an earlier hook refused the request: do
  /// not rely on state that [before] sets up.
  FutureOr<HttpResponse?> onError(HttpCtx c, Object error, StackTrace stack) =>
      null;
}
