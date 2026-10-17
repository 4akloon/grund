import 'package:grund/grund.dart';
import 'package:jaspr/server.dart';

import 'grund_scope.dart';
import 'page/page_match.dart';

/// The grund side of a page's [BuildContext]: the call scope of the request
/// it is rendered for, with the semantics of `HttpCtx`.
///
/// ```dart
/// final tasks = context.call<TasksService>().list();
/// final user = context.maybe<CurrentUser>();
/// ```
///
/// Each throws `MissingGrundScopeError` outside a page that `JasprModule`
/// renders.
extension GrundContext on BuildContext {
  /// The call scope: the bindings visible to `JasprModule`, plus the values
  /// hooks set for this request.
  Injector get injector => GrundScope.of(this).scope;

  /// The [T] (named [name]) of the call scope; throws when there is none.
  T call<T extends Object>([String? name]) => GrundScope.of(this).call<T>(name);

  /// The [T] (named [name]) of the call scope, or `null`.
  T? maybe<T extends Object>([String? name]) =>
      GrundScope.of(this).maybe<T>(name);

  /// The page this request matched, or `null` when it has none.
  PageMatch? get pageMatch => GrundScope.matchOf(this);
}
