import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'jaspr_error.dart';

/// Holds the [HttpCtx] of the request a page is rendered for; `JasprModule`
/// puts it above the application's root component.
///
/// Components reach it through the `BuildContext` extension
/// (`context.call<T>()`) or [of].
final class GrundScope extends InheritedComponent {
  /// Makes [httpContext] available to [child] and its descendants.
  const GrundScope({
    required this.httpContext,
    required super.child,
    super.key,
  });

  /// The context of the request being rendered.
  final HttpCtx httpContext;

  /// The request context above [context]; throws [MissingGrundScopeError]
  /// outside a page that `JasprModule` renders.
  static HttpCtx of(BuildContext context) =>
      context
          .dependOnInheritedComponentOfExactType<GrundScope>()
          ?.httpContext ??
      (throw const MissingGrundScopeError());

  @override
  bool updateShouldNotify(GrundScope oldComponent) =>
      !identical(httpContext, oldComponent.httpContext);
}
