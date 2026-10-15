import 'dart:async';

import '../pipeline/enhancers.dart';
import '../pipeline/execution_context.dart';
import '../pipeline/handler_spec.dart';

/// Handles a request with the controller instance and the request context.
/// The result is serialized into the response.
typedef RouteHandler<T> =
    FutureOr<Object?> Function(T controller, ExecutionContext context);

typedef _RouteOptions = ({
  String? name,
  Enhancers enhancers,
  List<Object> metadata,
});

/// An HTTP endpoint of a `Controller<T>`: method, path relative to the
/// controller path, and handler.
///
/// ```dart
/// Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param<int>('id')),
///     name: 'findOne');
/// ```
///
/// [path] may contain `:name` parameters and a trailing `*`. [name] defaults
/// to `'GET /:id'`; the generator passes the method name.
final class Route<T extends Object> extends HandlerSpec {
  /// A `GET` route.
  Route.get(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('GET', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `POST` route.
  Route.post(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('POST', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `PUT` route.
  Route.put(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('PUT', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `PATCH` route.
  Route.patch(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('PATCH', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `DELETE` route.
  Route.delete(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('DELETE', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  Route._(this.method, this.path, this.handler, _RouteOptions options)
    : super(
        name: options.name ?? '$method $path',
        enhancers: options.enhancers,
        metadata: options.metadata,
      );

  /// Upper-cased HTTP method.
  final String method;

  /// Path relative to the controller path.
  final String path;

  /// The handler.
  final RouteHandler<T> handler;

  @override
  FutureOr<Object?> invoke(Object target, ExecutionContext context) =>
      handler(target as T, context);

  @override
  String toString() => 'Route($method $path)';
}
