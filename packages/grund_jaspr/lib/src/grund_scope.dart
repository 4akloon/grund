import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'error/jaspr_error.dart';
import 'page/page_match.dart';

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
    this.pageMatch,
    super.key,
  });

  /// The context of the request being rendered.
  final HttpCtx httpContext;

  /// The page this request matched; `null` for a response that is no page of
  /// a site (the not-found page, the old application component).
  final PageMatch? pageMatch;

  /// The request context above [context]; throws [MissingGrundScopeError]
  /// outside a page that `JasprModule` renders.
  static HttpCtx of(BuildContext context) =>
      context
          .dependOnInheritedComponentOfExactType<GrundScope>()
          ?.httpContext ??
      (throw const MissingGrundScopeError());

  /// The match above [context]; `null` when the page has none. Throws
  /// [MissingGrundScopeError] outside a page that `JasprModule` renders.
  static PageMatch? matchOf(BuildContext context) =>
      (context.dependOnInheritedComponentOfExactType<GrundScope>() ??
              (throw const MissingGrundScopeError()))
          .pageMatch;

  @override
  bool updateShouldNotify(GrundScope oldComponent) =>
      !identical(httpContext, oldComponent.httpContext) ||
      !identical(pageMatch, oldComponent.pageMatch);
}
