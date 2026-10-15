import 'dart:async';

import '../ctx/http_ctx.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';

/// Handles one request: reads what it needs from [c] and returns the result.
///
/// The result is turned into the response: `null` is 204, an `HttpResponse`
/// is sent as it is, a `Stream<List<int>>` is streamed, `String` and
/// `Uint8List` are sent as text and bytes, anything else as JSON (through
/// `toJson()` or a registered `ResponseCodec`).
typedef RouteHandler = FutureOr<Object?> Function(HttpCtx c);

/// One route of an `HttpApi`: a method, a path below the API's path, the
/// [handler] and the hooks that wrap it.
///
/// ```dart
/// Route.get('/:id', (c) => users.find(c.path.integer('id')))
/// Route.post('/', (c) async => users.create(await c.body(NewUser.fromJson)),
///     status: 201, use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))])
/// ```
final class Route {
  Route._(
    this.method,
    this.path,
    this.handler, {
    this.status,
    this.use = const [],
    String? name,
  }) : name = name ?? '$method $path';

  /// A `GET` route; it also answers `HEAD`.
  Route.get(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('GET', path, handler, status: status, use: use, name: name);

  /// A `POST` route.
  Route.post(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('POST', path, handler, status: status, use: use, name: name);

  /// A `PUT` route.
  Route.put(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('PUT', path, handler, status: status, use: use, name: name);

  /// A `PATCH` route.
  Route.patch(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('PATCH', path, handler, status: status, use: use, name: name);

  /// A `DELETE` route.
  Route.delete(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('DELETE', path, handler, status: status, use: use, name: name);

  /// The upper-case HTTP method.
  final String method;

  /// The path below `HttpApi.path`: `/`, `/:id`, `/files/*`.
  final String path;

  /// Produces the result.
  final RouteHandler handler;

  /// The response status; it wins over `c.response.status` and the default.
  final int? status;

  /// Hooks that wrap only this route, after those of the API.
  final List<HookRef<HttpHook>> use;

  /// Names the route in errors; `'GET /:id'` unless given.
  final String name;
}
